#!/usr/bin/env bash
set -euo pipefail

# Helper script to label the GPU node for scheduling
# Usage: ./scripts/label-gpu-node.sh

cd "$(dirname "$0")/../tofu"

if [ -z "${KUBECONFIG:-}" ]; then
  echo "Error: KUBECONFIG not set. Run ./scripts/get-kubeconfig.sh first."
  exit 1
fi

if [ ! -f "terraform.tfstate" ]; then
  echo "Error: No terraform state found. Run 'tofu apply' first."
  exit 1
fi

GPU_WORKER_IP=$(tofu output -raw gpu_worker_ip 2>/dev/null)

if [ -z "$GPU_WORKER_IP" ]; then
  echo "Error: Could not find gpu_worker_ip in OpenTofu outputs"
  exit 1
fi

echo "Finding GPU worker node..."

# Find node by IP
NODE_NAME=$(kubectl get nodes -o json | \
  jq -r ".items[] | select(.status.addresses[] | select(.type==\"InternalIP\" and .address==\"$GPU_WORKER_IP\")) | .metadata.name")

if [ -z "$NODE_NAME" ]; then
  echo "Error: Could not find node with IP $GPU_WORKER_IP"
  echo "Nodes in cluster:"
  kubectl get nodes -o wide
  exit 1
fi

echo "Found GPU worker node: $NODE_NAME"
echo "Labeling node with accelerator=nvidia..."

kubectl label node "$NODE_NAME" accelerator=nvidia --overwrite

echo ""
echo "✓ GPU node labeled successfully!"
echo ""
echo "Verify with:"
echo "  kubectl get nodes --show-labels | grep accelerator"

