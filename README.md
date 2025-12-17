# OpenTofu + Proxmox GPU K3s Cluster

Automated provisioning of a GPU-enabled K3s cluster on Proxmox using OpenTofu. Designed for NVIDIA RTX 5060 Ti with open kernel modules.

## Features

- 🚀 Fully automated K3s cluster deployment
- 🎮 GPU passthrough with NVIDIA open kernel modules (580.105.08+)
- 🐧 Ubuntu 24.04 LTS base
- ☁️ Cloud-init for zero-touch provisioning
- 📦 NVIDIA device plugin for Kubernetes GPU scheduling
- 🔧 Node affinity support for GPU workloads

## Architecture

- **1 Control Plane Node**: K3s server (CPU-only)
- **2 Worker Nodes**: Standard K3s agents (CPU-only)
- **1 GPU Worker Node**: K3s agent with NVIDIA RTX 5060 Ti passthrough

## Prerequisites

- Proxmox VE 8.x
- NVIDIA GPU with passthrough enabled
- IOMMU enabled in BIOS and Proxmox
- At least 30GB free storage per VM (120GB total)
- Storage named `local` for cloud image download
- OpenTofu 1.10.1+ installed locally
- kubectl installed locally

## Quick Start

### 1. Create Proxmox API Token

See [docs/proxmox-api-token.md](docs/proxmox-api-token.md)

```bash
# On Proxmox host
pveum user token add root@pam tofu --privsep 0
```

### 2. Get Your SSH Key

```bash
curl https://github.com/<your_github_user>.keys
```

### 3. Configure Variables

```bash
cd tofu/env
cp lab.tfvars.example lab.tfvars
nano lab.tfvars
```

Update with your values:
- `proxmox_api_token`: Token from step 1
- `ssh_public_keys`: Your SSH key from step 2
- `gpu_pci_id`: Verify with `ssh root@192.168.0.37 "lspci | grep -i nvidia"`

### 4. Deploy Cluster

```bash
cd tofu
tofu init
tofu plan -var-file=env/lab.tfvars
tofu apply -var-file=env/lab.tfvars
```

Wait 5-10 minutes for cloud image download and VMs to boot and complete cloud-init.

### 5. Get Kubeconfig

```bash
# Get server IP from OpenTofu output
SERVER_IP=$(tofu output -raw k3s_server_ip)

# Copy kubeconfig
ssh ubuntu@$SERVER_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | \
  sed "s/127.0.0.1/$SERVER_IP/" > kubeconfig

# Test access
export KUBECONFIG=./kubeconfig
kubectl get nodes -o wide
```

### 6. Label GPU Node

```bash
kubectl label node k3s-gpu-worker-0 accelerator=nvidia
```

### 7. Deploy NVIDIA Device Plugin

```bash
kubectl apply -f ../k8s/nvidia-device-plugin.yaml
```

### 8. Verify GPU

```bash
# Check node has GPU capacity
kubectl describe node k3s-gpu-worker-0 | grep -A5 Capacity

# Should show:
#   nvidia.com/gpu: 1
```

### 9. Test GPU Workload

```bash
kubectl apply -f ../k8s/test-gpu-pod.yaml
kubectl logs nvidia-smi-test
```

You should see nvidia-smi output showing your RTX 5060 Ti!

## Project Structure

```
.
├── README.md                         # This file
├── opentofu-proxmox-k3s-gpu.md      # Reference documentation
├── docs/
│   ├── ubuntu-template-setup.md      # Manual template (reference only, not required)
│   ├── proxmox-api-token.md          # API token setup
│   └── troubleshooting.md            # Common issues and fixes
├── tofu/
│   ├── versions.tf                   # OpenTofu version constraints
│   ├── providers.tf                  # Proxmox provider config
│   ├── variables.tf                  # Input variables
│   ├── outputs.tf                    # Cluster information outputs
│   ├── main.tf                       # Module composition
│   ├── env/
│   │   └── lab.tfvars.example        # Example configuration
│   └── modules/
│       ├── k3s_server/               # Control plane module
│       ├── k3s_worker/               # Worker node module
│       └── k3s_gpu_worker/           # GPU worker module
└── k8s/
    ├── nvidia-device-plugin.yaml     # GPU device plugin
    └── test-gpu-pod.yaml             # GPU validation pod
```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `proxmox_endpoint` | Proxmox API URL | - |
| `proxmox_api_token` | API token | - |
| `proxmox_node` | Proxmox node name | - |
| `vm_disk_size_gb` | Disk size per VM | `30` |
| `k3s_version` | K3s version | `v1.30.8+k3s1` |
| `nvidia_driver_version` | NVIDIA driver series | `580` |
| `gpu_pci_id` | GPU PCI address | - |
| `worker_count` | Non-GPU workers | `2` |

See `tofu/variables.tf` for complete list.

## Deploying GPU Workloads

Use node affinity to schedule pods on the GPU node:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-gpu-app
spec:
  containers:
  - name: app
    image: my-gpu-image
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    accelerator: nvidia
```

## Maintenance

### Upgrading K3s

1. Update `k3s_version` in `lab.tfvars`
2. Run `tofu apply -var-file=env/lab.tfvars`
3. VMs will be recreated with new version

### Upgrading NVIDIA Drivers

1. Update `nvidia_driver_version` in `lab.tfvars`
2. Run `tofu apply -var-file=env/lab.tfvars`
3. GPU worker will be recreated

### Scaling Workers

1. Update `worker_count` in `lab.tfvars`
2. Run `tofu apply -var-file=env/lab.tfvars`

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues.

Quick checks:

```bash
# Check cloud-init status on a VM
ssh ubuntu@<vm-ip> "cloud-init status"

# Check K3s server logs
ssh ubuntu@<server-ip> "sudo journalctl -u k3s -f"

# Check GPU worker bootstrap
ssh ubuntu@<gpu-worker-ip> "tail -f /var/log/bootstrap-gpu-worker.log"

# Check NVIDIA driver
ssh ubuntu@<gpu-worker-ip> "nvidia-smi"

# Check device plugin
kubectl logs -n nvidia-device-plugin -l name=nvidia-device-plugin-ds
```

## Design Decisions

- **Cloud-init over Ansible**: Simpler for day-0 provisioning, sufficient for immutable infrastructure approach
- **K3s over K8s**: Lighter weight, faster iteration, perfect for homelab
- **NVIDIA Device Plugin over GPU Operator**: Focused, simpler, less overhead
- **NVIDIA Open Kernel Modules**: Better compatibility with modern kernels, avoids DKMS issues
- **One GPU per VM**: Simpler passthrough, better isolation

## Roadmap

- [ ] Add Packer automation for template creation
- [ ] Add Ansible playbooks for day-2 operations
- [ ] Add multi-control-plane HA setup
- [ ] Add Cilium CNI option
- [ ] Add Longhorn storage integration
- [ ] Add ArgoCD for GitOps

## References

- [OpenTofu Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [K3s Documentation](https://docs.k3s.io)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [NVIDIA Open GPU Kernel Modules](https://github.com/NVIDIA/open-gpu-kernel-modules)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com)

## License

MIT

## Contributing

Issues and pull requests welcome!
