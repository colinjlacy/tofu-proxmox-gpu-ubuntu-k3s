#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import time
import requests
from typing import Optional

PROMPTS = [
    "Explain what an LLM is in one sentence.",
    "Give a 3-bullet checklist for debugging Kubernetes pods.",
    "Write a haiku about GPUs.",
    "What does vLLM do?",
    "Explain concurrency in simple terms.",
]

def parse_sse_stream(response, endpoint: str, debug: bool = False) -> str:
    """Parse Server-Sent Events stream and accumulate the complete response."""
    accumulated_text = ""
    chunk_count = 0
    total_lines = 0
    empty_content_count = 0
    
    for line in response.iter_lines(decode_unicode=True):
        if not line:
            continue
        
        total_lines += 1
        
        # SSE data lines start with "data: "
        if line.startswith("data: "):
            data_str = line[6:].strip()  # Remove "data: " prefix
            
            # "[DONE]" signals end of stream
            if data_str == "[DONE]":
                if debug:
                    print(f"DEBUG: Stream ended - {total_lines} lines, {chunk_count} content chunks, {empty_content_count} empty, total text: {len(accumulated_text)}")
                break
            
            try:
                data = json.loads(data_str)
                
                if debug and chunk_count < 3:  # Only print first 3 complete JSON objects
                    print(f"DEBUG chunk {chunk_count}: {json.dumps(data)[:200]}")
                
                if endpoint == "/v1/chat/completions":
                    # Try multiple possible locations for content
                    choices = data.get("choices", [])
                    if choices:
                        choice = choices[0]
                        delta = choice.get("delta", {})
                        # Only get actual content, skip reasoning
                        content = delta.get("content")
                        # If content key doesn't exist, try message.content
                        if content is None:
                            message = choice.get("message", {})
                            content = message.get("content", "")
                        # Track empty content
                        if not content:
                            empty_content_count += 1
                            content = ""
                else:
                    choices = data.get("choices", [])
                    if choices:
                        content = choices[0].get("text", "")
                
                if content:
                    if debug:
                        print(f"DEBUG: Found content: {content[:50]}")
                    accumulated_text += content
                    chunk_count += 1
            except (json.JSONDecodeError, IndexError, KeyError) as e:
                if debug:
                    print(f"DEBUG: Parse error: {e} for data: {data_str[:100]}")
                continue
    
    if debug and total_lines > 0:
        print(f"DEBUG: Returning text of length {len(accumulated_text)}")
    
    return accumulated_text

def send_request(
    idx: int,
    base_url: str,
    model: Optional[str],
    max_tokens: int,
    temperature: float,
    timeout: int,
    api_key: Optional[str],
    endpoint: str,
    debug: bool = False,
) -> dict:
    prompt = PROMPTS[idx % len(PROMPTS)]
    
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    
    if endpoint == "/v1/chat/completions":
        payload = {
            "messages": [
                {"role": "system", "content": "You are a helpful assistant. Keep responses brief."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
        }
    else:
        payload = {
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
        }
    
    if model:
        payload["model"] = model
    
    url = f"{base_url}{endpoint}"
    start = time.time()
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=timeout, stream=True)
        status_code = response.status_code
        
        if status_code != 200:
            latency = time.time() - start
            print(f"[{idx}] ERROR {latency:.2f}s (HTTP {status_code})")
            return {"success": False, "latency": latency, "tokens": 0, "error": f"HTTP {status_code}"}
        
        # Parse the SSE stream
        text = parse_sse_stream(response, endpoint, debug)
        
        latency = time.time() - start
        # Estimate tokens (rough approximation: ~4 chars per token)
        tokens = len(text) // 4 if text else 0
        
        # Truncate for display
        display_text = text.replace("\n", " ")[:256] if text else "(empty response)"
        print(f"[{idx}] HTTP {status_code} {latency:.2f}s  {display_text}")
        
        return {"success": True, "latency": latency, "tokens": tokens, "text_length": len(text)}
    
    except requests.exceptions.Timeout:
        latency = time.time() - start
        print(f"[{idx}] ERROR {latency:.2f}s (timeout)")
        return {"success": False, "latency": latency, "tokens": 0, "error": "timeout"}
    except requests.exceptions.HTTPError as e:
        latency = time.time() - start
        print(f"[{idx}] ERROR {latency:.2f}s (HTTP error: {e})")
        return {"success": False, "latency": latency, "tokens": 0, "error": f"HTTP error: {e}"}
    except Exception as e:
        latency = time.time() - start
        print(f"[{idx}] ERROR {latency:.2f}s ({type(e).__name__}: {str(e)})")
        return {"success": False, "latency": latency, "tokens": 0, "error": f"{type(e).__name__}: {str(e)}"}

def main():
    parser = argparse.ArgumentParser(description="Send concurrent requests to LLM API")
    parser.add_argument("--base-url", default="http://localhost:8000", help="Base URL (default: http://localhost:8000)")
    parser.add_argument("--model", default=None, help="Optional model name")
    parser.add_argument("-c", "--concurrency", type=int, default=10, help="Number of concurrent requests (default: 10)")
    parser.add_argument("--max-tokens", type=int, default=2048, help="Max tokens (default: 512)")
    parser.add_argument("--temperature", type=float, default=0.2, help="Temperature (default: 0.2)")
    parser.add_argument("--timeout", type=int, default=120, help="Per-request timeout in seconds (default: 120)")
    parser.add_argument("--api-key", default=None, help="Optional API key")
    parser.add_argument("--completions", action="store_true", help="Use /v1/completions instead of chat")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    
    args = parser.parse_args()
    
    if args.concurrency < 1:
        print("ERROR: --concurrency must be >= 1")
        return 1
    
    endpoint = "/v1/completions" if args.completions else "/v1/chat/completions"
    
    print(f"Sending {args.concurrency} concurrent requests to {args.base_url}{endpoint}")
    if args.model:
        print(f"Including model field: {args.model}")
    else:
        print("Omitting model field (server default)")
    print()
    
    overall_start = time.time()
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [
            executor.submit(
                send_request,
                idx,
                args.base_url,
                args.model,
                args.max_tokens,
                args.temperature,
                args.timeout,
                args.api_key,
                endpoint,
                args.debug,
            )
            for idx in range(args.concurrency)
        ]
        # Wait for all to complete and collect results
        results = [future.result() for future in concurrent.futures.as_completed(futures)]
    
    overall_time = time.time() - overall_start
    
    # Calculate statistics
    success_count = sum(1 for r in results if r["success"])
    error_count = len(results) - success_count
    latencies = [r["latency"] for r in results]
    total_tokens = sum(r["tokens"] for r in results)
    
    # Print summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print(f"Total time:           {overall_time:.2f}s")
    print(f"Successful responses: {success_count}")
    print(f"Error responses:      {error_count}")
    if latencies:
        print(f"Shortest latency:     {min(latencies):.2f}s")
        print(f"Longest latency:      {max(latencies):.2f}s")
        print(f"Average latency:      {sum(latencies)/len(latencies):.2f}s")
    print(f"Total tokens:         ~{total_tokens} (estimated)")
    print("="*60)

if __name__ == "__main__":
    main()

