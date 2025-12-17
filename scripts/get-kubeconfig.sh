#!/usr/bin/env bash
set -euo pipefail

# Helper script to retrieve and configure kubeconfig from K3s server
# Usage: ./scripts/get-kubeconfig.sh [output-file]

cd "$(dirname "$0")/../tofu"

OUTPUT_FILE="${1:-./kubeconfig}"

if [ ! -f "terraform.tfstate" ]; then
  echo "Error: No terraform state found. Run 'tofu apply' first."
  exit 1
fi

# Get server IP from OpenTofu state
SERVER_IP=$(tofu output -raw k3s_server_ip 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
  echo "Error: Could not find k3s_server_ip in OpenTofu outputs"
  exit 1
fi

echo "Retrieving kubeconfig from K3s server at $SERVER_IP..."

ssh -o StrictHostKeyChecking=accept-new ubuntu@"$SERVER_IP" \
  "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null | \
  sed "s/127.0.0.1/$SERVER_IP/" > "$OUTPUT_FILE" || {
  echo ""
  echo "Error: Could not retrieve kubeconfig. Possible issues:"
  echo "  - SSH key not added to your agent"
  echo "  - Server not fully booted yet (wait 2-3 minutes)"
  echo "  - K3s server installation failed (check logs on server)"
  exit 1
}

chmod 600 "$OUTPUT_FILE"

echo ""
echo "✓ Kubeconfig saved to: $OUTPUT_FILE"
echo ""
echo "To use it:"
echo "  export KUBECONFIG=$OUTPUT_FILE"
echo "  kubectl get nodes"

