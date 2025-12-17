#!/usr/bin/env bash
set -euo pipefail

# Helper script to deploy NVIDIA device plugin
# Usage: ./scripts/deploy-gpu-plugin.sh

if [ -z "${KUBECONFIG:-}" ]; then
  echo "Error: KUBECONFIG not set. Run ./scripts/get-kubeconfig.sh first."
  exit 1
fi

cd "$(dirname "$0")/.."

echo "Deploying NVIDIA device plugin..."
kubectl apply -f k8s/nvidia-device-plugin.yaml

echo ""
echo "Waiting for device plugin to be ready..."
kubectl wait --for=condition=ready pod \
  -l name=nvidia-device-plugin-ds \
  -n nvidia-device-plugin \
  --timeout=120s || {
  echo ""
  echo "Warning: Device plugin pods not ready yet. Check logs:"
  echo "  kubectl logs -n nvidia-device-plugin -l name=nvidia-device-plugin-ds"
  exit 1
}

echo ""
echo "✓ NVIDIA device plugin deployed successfully!"
echo ""
echo "Verify GPU capacity:"
echo "  kubectl get nodes -o json | jq '.items[].status.capacity | select(.\"nvidia.com/gpu\")'"

