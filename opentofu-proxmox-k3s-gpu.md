# OpenTofu + Proxmox GPU K3s Cluster (Ubuntu 24.04 LTS) — Reference Project

This document describes a practical OpenTofu project that provisions **Ubuntu 24.04 LTS GPU worker VMs on Proxmox**, installs the **NVIDIA open kernel modules**, and joins them to a **K3s** cluster. It then deploys the **NVIDIA Kubernetes device plugin** (not the GPU Operator) to expose GPUs to workloads.

It is written to be dropped into a Git repository as a starting point you can tailor to your environment.

---

## Goals

- Use **OpenTofu** as the “source of truth” for:
  - VM lifecycle on **Proxmox**
  - VM sizing and placement
  - **PCIe GPU passthrough attachment** to worker VMs
  - cloud-init injection of initial bootstrap configuration
- Use **Ubuntu 24.04 LTS** on GPU workers for broad ecosystem compatibility
- Use **NVIDIA open kernel modules** (avoids the proprietary-module mismatch you hit and plays well with Secure Boot when using the open modules)
- Use **K3s** first (lighter footprint, faster iteration)
- Use **NVIDIA device plugin** (simple + focused) rather than the NVIDIA GPU Operator initially

---

## High-level architecture

### Nodes
- **k3s-server VM(s)** (CPU-only; no GPU required)
  - Runs K3s server
  - Exposes join token to workers (via output, file, or a secure channel)
- **k3s-agent GPU worker VMs** (one per GPU, or multiple if you prefer, depending on passthrough strategy)
  - GPU passed through via Proxmox PCI device assignment
  - Installs NVIDIA drivers (open kernel modules) + container runtime integration
  - Installs K3s agent and joins the cluster
  - GPU is advertised to Kubernetes via NVIDIA device plugin

### Automation layers
- **OpenTofu** (IaC): Proxmox VMs + passthrough + cloud-init config
- **cloud-init** (guest bootstrap): install packages, configure NVIDIA runtime, install K3s agent, validate GPU
- **kubectl apply** (post-provision): deploy NVIDIA device plugin DaemonSet

> Optional: Add Ansible later for “day-2” configuration drift management and upgrades.

---

## Explicit provider choice: Proxmox OpenTofu provider

This project explicitly uses the **Proxmox OpenTofu provider** to provision VMs and attach PCI devices.

Two commonly used providers you may encounter are:
- `bpg/proxmox` (actively used/maintained by community; modern resource model)
- `telmate/proxmox` (older, still widely referenced)

This reference layout assumes **`bpg/proxmox`** and shows where provider configuration lives. If you prefer another provider, keep the same module structure and swap resources accordingly.

---

## Repo layout

```text
tofu-proxmox-k3s-gpu/
├── README.md                         # (optional) short entrypoint; can be this file
├── tofu/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── main.tf                        # calls modules
│   ├── env/
│   │   ├── lab.tfvars                 # your environment values (not committed)
│   │   └── prod.tfvars                # optional
│   └── modules/
│       ├── ubuntu_vm/
│       │   ├── main.tf                # VM resource (Proxmox)
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── cloudinit/
│       │       ├── user-data.yaml.tftpl
│       │       └── meta-data.yaml.tftpl
│       ├── k3s_server/
│       │   ├── main.tf                # VM + cloud-init for server
│       │   ├── variables.tf
│       │   ├── outputs.tf             # join token, kubeconfig retrieval notes
│       │   └── cloudinit/
│       │       └── user-data.yaml.tftpl
│       └── k3s_gpu_worker/
│           ├── main.tf                # VM + GPU passthrough + cloud-init for worker
│           ├── variables.tf
│           ├── outputs.tf
│           └── cloudinit/
│               └── user-data.yaml.tftpl
└── k8s/
    └── nvidia-device-plugin.yaml      # pinned version manifest (no GPU Operator)
```

### What belongs where
- `tofu/`: everything OpenTofu needs to create/modify infrastructure
- `tofu/modules/*`: reusable building blocks for VMs
- `k8s/`: manifests applied after the cluster exists

---

## Decisions and trade-offs: cloud-init vs Ansible

### Why cloud-init is chosen initially
**cloud-init** is used for the first iteration because it:
- Runs on first boot, which maps well to “new VM becomes a node” workflows
- Keeps the number of moving parts low (no separate control host required)
- Works extremely well with Ubuntu images/templates and Proxmox cloud-init integration
- Is sufficient for “day-0 / day-1” configuration:
  - install NVIDIA packages (open kernel module path)
  - configure NVIDIA container runtime for containerd
  - install and start K3s agent
  - run basic validation (`nvidia-smi`)

### Trade-offs of cloud-init (explicit)
cloud-init is not a full configuration management system:
- **Idempotency**: you must design scripts to be safely re-runnable or accept “first boot only” behavior
- **Day-2 changes**: driver upgrades, K3s upgrades, containerd config changes are harder to manage
- **Observability**: debugging is “log into VM + check `/var/log/cloud-init*`”, which is fine but less structured than Ansible runs
- **Secure Boot enrollment**: if a workflow requires interactive MOK enrollment, cloud-init cannot do that unattended (for the open modules this is generally less painful, but still worth noting)

### When Ansible becomes the better choice
Add Ansible when you want:
- consistent upgrades (kernel/driver/K3s) across many nodes
- drift control and reporting
- multi-environment promotion (lab → staging → prod)
- more complex logic (e.g., detecting specific PCI IDs and selecting module flavors, gating reboots)

### Recommended hybrid approach (best of both)
- Keep cloud-init for **base bootstrap** (SSH keys, packages, join K3s)
- Use Ansible later for **day-2 lifecycle** (upgrades, tuning, security hardening)

---

## Implementation details

### 1) Proxmox VM templates
This project assumes you have a Proxmox VM template for Ubuntu 24.04 LTS with:
- cloud-init enabled
- q35 machine type recommended for GPU passthrough scenarios
- OVMF (UEFI) recommended

You can build templates with Packer later (optional). For now, a manual template is fine.

### 2) GPU passthrough strategy
For simplicity and reliability:
- **One GPU per VM** (pass through the entire device)
- Add the GPU device in OpenTofu using the Proxmox provider’s PCI device options
- Include audio function (same IOMMU group) where relevant

### 3) Secure Boot stance (practical)
To keep provisioning fully unattended:
- Preferred: **Disable Secure Boot for GPU worker VMs** in OVMF, OR pre-enroll keys in a golden image.
- If you keep Secure Boot on:
  - Open modules are friendlier, but any module-signing/enrollment steps can still require a console interaction depending on your exact setup.

This document assumes you aim for unattended provisioning; therefore it recommends either disabling Secure Boot on the VM or baking enrollment into the template if you keep it enabled.

### 4) NVIDIA “open kernel modules” selection
Ubuntu packages you will commonly use for the open kernel module path (exact names can vary by driver branch):
- `nvidia-dkms-<branch>-open` (e.g., `nvidia-dkms-580-open`)
- `nvidia-utils-<branch>`
- `nvidia-container-toolkit`

In cloud-init you can:
- pin a driver branch (e.g., 580) if you want stable reproducibility
- or allow the distro to select a supported branch

---

## Example OpenTofu configuration (skeleton)

> **Note:** Resource names/arguments vary slightly by provider version. Treat these as a *shape* to implement, not a copy/paste final file.

### `tofu/versions.tf`
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.6" # example; pin to what you test
    }
  }
}
```

### `tofu/providers.tf`
```hcl
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token

  # If you use self-signed certs
  insecure = var.proxmox_insecure
}
```

### `tofu/main.tf` (wiring modules)
```hcl
module "k3s_server" {
  source = "./modules/k3s_server"

  name_prefix      = var.name_prefix
  proxmox_node     = var.proxmox_node
  template_id      = var.ubuntu_template_id
  vm_network_bridge = var.vm_network_bridge

  server_ip_cidr   = var.k3s_server_ip_cidr
  ssh_public_keys  = var.ssh_public_keys

  k3s_version      = var.k3s_version
}

module "gpu_workers" {
  source = "./modules/k3s_gpu_worker"

  for_each = var.gpu_workers

  name_prefix        = var.name_prefix
  proxmox_node       = var.proxmox_node
  template_id        = var.ubuntu_template_id
  vm_network_bridge  = var.vm_network_bridge

  worker_ip_cidr     = each.value.ip_cidr
  ssh_public_keys    = var.ssh_public_keys

  # GPU passthrough
  gpu_pci_id         = each.value.gpu_pci_id  # e.g. "0000:01:00.0"
  gpu_all_functions  = true

  # Join the cluster
  k3s_server_url     = module.k3s_server.server_url
  k3s_join_token     = module.k3s_server.join_token

  k3s_version        = var.k3s_version

  # NVIDIA
  nvidia_driver_branch = var.nvidia_driver_branch # e.g. "580"
}
```

### `tofu/variables.tf` (key inputs)
```hcl
variable "proxmox_endpoint" { type = string }
variable "proxmox_api_token" { type = string }
variable "proxmox_insecure" { type = bool  default = true }

variable "proxmox_node" { type = string }

variable "ubuntu_template_id" { type = string }
variable "vm_network_bridge" { type = string }

variable "name_prefix" { type = string }

variable "ssh_public_keys" {
  type = list(string)
}

variable "k3s_version" {
  type    = string
  default = "v1.30.5+k3s1" # example
}

variable "nvidia_driver_branch" {
  type    = string
  default = "580"
}

# Map of GPU workers you want to create
variable "gpu_workers" {
  type = map(object({
    ip_cidr   = string
    gpu_pci_id = string
  }))
}
```

---

## Module behavior (what each module does)

### `modules/k3s_server`
**Responsibilities**
- Clone Ubuntu 24.04 template
- Apply cloud-init (user-data) that:
  - installs K3s server
  - stores join token
  - optionally writes kubeconfig to a known location
- Outputs:
  - `server_url` (e.g., `https://<server-ip>:6443`)
  - `join_token` (retrieved from server via cloud-init strategy, or through a post-provision read step)

**Trade-off note:** Getting the join token as an OpenTofu output can be done a few ways:
- *Simple/dev*: run a one-time command manually on the server and paste token into tfvars
- *Automated*: use a provisioner/remote-exec or a small sidecar process to read `/var/lib/rancher/k3s/server/node-token`
- *Most secure*: use a secrets manager and inject token to workers

For an initial lab build, the simple/dev approach is totally fine.

### `modules/k3s_gpu_worker`
**Responsibilities**
- Clone Ubuntu 24.04 template
- Attach GPU PCI device in Proxmox settings (via provider)
- Apply cloud-init (user-data) that:
  - installs NVIDIA open kernel module packages for your chosen branch
  - installs and configures `nvidia-container-toolkit`
  - configures containerd (used by K3s) to enable NVIDIA runtime
  - installs K3s agent and joins the cluster
  - validates `nvidia-smi` and writes a marker file if successful

---

## cloud-init templates (key ideas)

### GPU worker `cloudinit/user-data.yaml.tftpl` (conceptual)
```yaml
#cloud-config
package_update: true
package_upgrade: false

write_files:
  - path: /usr/local/bin/bootstrap-gpu-worker.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      echo "[bootstrap] Installing prerequisites"
      apt-get update
      apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg dkms build-essential linux-headers-$(uname -r)

      echo "[bootstrap] Installing NVIDIA open kernel modules (branch ${nvidia_driver_branch})"
      apt-get install -y --no-install-recommends \
        nvidia-dkms-${nvidia_driver_branch}-open \
        nvidia-utils-${nvidia_driver_branch} \
        nvidia-container-toolkit

      echo "[bootstrap] Configure NVIDIA runtime for containerd"
      nvidia-ctk runtime configure --runtime=containerd || true

      # K3s uses containerd; restart to pick up config changes
      systemctl restart containerd || true

      echo "[bootstrap] Validate driver"
      nvidia-smi || (echo "nvidia-smi failed" && exit 1)

      echo "[bootstrap] Install and join K3s agent"
      curl -sfL https://get.k3s.io | \
        K3S_URL="${k3s_server_url}" \
        K3S_TOKEN="${k3s_join_token}" \
        INSTALL_K3S_VERSION="${k3s_version}" \
        sh -

      echo "[bootstrap] Done"
      touch /var/lib/bootstrap-gpu-worker.ok

runcmd:
  - [ bash, -lc, "/usr/local/bin/bootstrap-gpu-worker.sh > /var/log/bootstrap-gpu-worker.log 2>&1" ]
```

**Notes**
- This template uses the official K3s install script for simplicity (common in labs). You can pin checksums later.
- The script installs the open modules explicitly. If your GPU requires open modules, this avoids the proprietary mismatch.
- It validates `nvidia-smi` before joining K3s, so you don’t add broken nodes into the cluster.

### Server `cloudinit/user-data.yaml.tftpl` (conceptual)
```yaml
#cloud-config
package_update: true
package_upgrade: false

write_files:
  - path: /usr/local/bin/bootstrap-k3s-server.sh
    permissions: "0755"
    content: |
      #!/usr/bin/env bash
      set -euo pipefail

      curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="${k3s_version}" \
        sh -s - server --write-kubeconfig-mode 0644

      # token location: /var/lib/rancher/k3s/server/node-token
      cp /var/lib/rancher/k3s/server/node-token /root/k3s-node-token
      chmod 0600 /root/k3s-node-token

runcmd:
  - [ bash, -lc, "/usr/local/bin/bootstrap-k3s-server.sh > /var/log/bootstrap-k3s-server.log 2>&1" ]
```

---

## Deploying the NVIDIA device plugin (post-provision)

Once your cluster is up and workers have joined, apply the NVIDIA device plugin manifest.

### Approach
- Keep the manifest in `k8s/nvidia-device-plugin.yaml`
- Pin the version you deploy (don’t use “latest”)

### Example workflow
```bash
# Set KUBECONFIG to your server kubeconfig
export KUBECONFIG=./kubeconfig

kubectl apply -f k8s/nvidia-device-plugin.yaml

# Verify nodes advertise GPUs
kubectl describe node <gpu-worker-node> | grep -i nvidia -A3

# Run a quick validation Pod
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-smi
spec:
  restartPolicy: Never
  containers:
  - name: nvidia-smi
    image: nvidia/cuda:12.4.1-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

---

## Operational notes

### GPU passthrough and scheduling
- Start with **1 GPU per worker VM**
- Label GPU workers:
  ```bash
  kubectl label node <node> accelerator=nvidia
  ```
- Use node selectors / taints to keep GPU workloads on GPU nodes.

### Upgrades
- For the first iteration:
  - rebuild VMs from scratch (immutable approach) when you want to upgrade drivers/K3s
- Later:
  - introduce Ansible to upgrade in place, coordinate reboots, and validate health

### Logging and debugging
- cloud-init logs:
  - `/var/log/cloud-init.log`
  - `/var/log/cloud-init-output.log`
  - `/var/log/bootstrap-*.log` (as created above)

---

## Security notes (token handling)
For a lab, passing `K3S_TOKEN` through cloud-init is fine.
For anything sensitive:
- store the token in a secrets manager
- or use a short-lived join token flow
- lock down metadata exposure

---

## Next extensions (optional)
- Add a `packer/` directory to build the Ubuntu template automatically
- Add an Ansible playbook for day-2 operations
- Add multi-server (HA) K3s
- Add Cilium networking
- Add a storage solution (Longhorn, Ceph, etc.)

---

## Summary
This OpenTofu project approach gives you:
- Proxmox-native VM provisioning and GPU passthrough **via the Proxmox OpenTofu provider**
- Fast, repeatable K3s cluster creation
- NVIDIA open kernel modules to avoid driver/module mismatches
- A minimal, understandable GPU enablement path using the NVIDIA device plugin

It’s optimized for a homelab-to-prod progression: start simple, then add structure (Packer/Ansible/secrets management) when the cluster is stable.
