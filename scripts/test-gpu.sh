#!/usr/bin/env bash
set -euo pipefail

# Helper script to test GPU functionality
# Usage: ./scripts/test-gpu.sh

if [ -z "${KUBECONFIG:-}" ]; then
  echo "Error: KUBECONFIG not set. Run ./scripts/get-kubeconfig.sh first."
  exit 1
fi

cd "$(dirname "$0")/.."

echo "Deploying GPU test pod..."
kubectl apply -f k8s/test-gpu-pod.yaml

echo ""
echo "Waiting for pod to complete..."
kubectl wait --for=condition=ready pod/nvidia-smi-test --timeout=60s 2>/dev/null || true

# Wait a bit for the command to run
sleep 5

echo ""
echo "=== GPU Test Results ==="
echo ""
kubectl logs nvidia-smi-test || {
  echo "Error: Could not get pod logs. Pod may still be starting."
  echo ""
  echo "Check status with:"
  echo "  kubectl get pod nvidia-smi-test"
  echo "  kubectl describe pod nvidia-smi-test"
  exit 1
}

echo ""
echo "=== Pod Events ==="
kubectl get events --field-selector involvedObject.name=nvidia-smi-test --sort-by='.lastTimestamp' | tail -10

echo ""
echo "✓ GPU test complete! If you see nvidia-smi output above, your GPU is working."
echo ""
echo "Clean up test pod with:"
echo "  kubectl delete pod nvidia-smi-test"

