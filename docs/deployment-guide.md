# Complete Deployment Guide

This guide walks through the entire process from scratch to a working GPU-enabled K3s cluster.

## Prerequisites Checklist

- [ ] Proxmox VE 8.x installed
- [ ] IOMMU enabled in BIOS
- [ ] IOMMU enabled in Proxmox (`/etc/default/grub`)
- [ ] NVIDIA GPU visible in Proxmox (`lspci | grep -i nvidia`)
- [ ] At least 120GB free storage (4 VMs × 30GB)
- [ ] OpenTofu 1.10.1+ installed on your workstation
- [ ] kubectl installed on your workstation
- [ ] jq installed on your workstation (for helper scripts)

## Step 1: Verify Proxmox GPU Setup

SSH to your Proxmox host:

```bash
ssh root@192.168.0.37
```

Check IOMMU is enabled:

```bash
dmesg | grep -e DMAR -e IOMMU
# Should see output about IOMMU being enabled
```

Identify your GPU PCI ID:

```bash
lspci -nn | grep -i nvidia
# Example output: 00:10.0 VGA compatible controller [0300]: NVIDIA Corporation...
# Your PCI ID is 00000000:00:10.0 (format: domain:bus:slot.function)
```

Verify GPU is not currently in use by any VM:

```bash
qm list
# Make sure no VMs are using the GPU
```

## Step 2: Create Proxmox API Token

In Proxmox web UI (https://192.168.0.37:8006):

1. Navigate to **Datacenter → Permissions → API Tokens**
2. Click **Add**
3. Configure:
   - User: `root@pam`
   - Token ID: `tofu`
   - Privilege Separation: **Uncheck**
4. Click **Add**
5. **COPY THE SECRET IMMEDIATELY** (shown only once)

Format: `root@pam!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

## Step 3: Create Ubuntu 24.04 Template

Still on the Proxmox host:

```bash
# Download cloud image
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Create template VM
VM_ID=9000
qm create $VM_ID \
  --name ubuntu-2404-cloud-init \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci

# Import and attach disk
qm importdisk $VM_ID noble-server-cloudimg-amd64.img local-lvm
qm set $VM_ID --scsi0 local-lvm:vm-$VM_ID-disk-0

# Add cloud-init drive
qm set $VM_ID --ide2 local-lvm:cloudinit

# Configure boot
qm set $VM_ID --boot c --bootdisk scsi0

# Add serial console
qm set $VM_ID --serial0 socket --vga serial0

# Enable guest agent
qm set $VM_ID --agent enabled=1

# Set machine type for GPU passthrough
qm set $VM_ID --machine q35

# Set UEFI/OVMF
qm set $VM_ID --efidisk0 local-lvm:1,format=raw
qm set $VM_ID --bios ovmf

# Convert to template
qm template $VM_ID

# Verify
qm list | grep $VM_ID
```

## Step 4: Clone Repository and Configure

On your workstation:

```bash
cd ~/projects  # or wherever you keep projects
# If this is a git repo, clone it. Otherwise you already have it.

# Navigate to the project
cd tofu-proxmox-gpu-ubuntu-k3s

# Create your configuration
cd tofu/env
cp lab.tfvars.example lab.tfvars
```

Edit `lab.tfvars`:

```bash
nano lab.tfvars
```

Update these values:
- `proxmox_api_token`: Paste token from Step 2
- `ssh_public_keys`: Add your SSH key (get from https://github.com/colinjlacy.keys)
- `gpu_pci_id`: Use PCI ID from Step 1 (format: `00000000:00:10.0`)
- `ubuntu_template_id`: Use template ID from Step 3 (default: `"9000"`)

Save and close.

## Step 5: Initialize OpenTofu

```bash
cd tofu
tofu init
```

Expected output:
```
Initializing provider plugins...
- Installing bpg/proxmox...
OpenTofu has been successfully initialized!
```

## Step 6: Plan and Review

```bash
tofu plan -var-file=env/lab.tfvars
```

Review the plan. You should see:
- 1 K3s server VM
- 2 K3s worker VMs
- 1 K3s GPU worker VM
- 4 cloud-init config files
- Total: ~8 resources to create

## Step 7: Deploy Cluster

```bash
tofu apply -var-file=env/lab.tfvars
```

Type `yes` when prompted.

**Wait 5-10 minutes** for VMs to boot and cloud-init to complete.

Monitor progress (in separate terminal):

```bash
# Watch VM creation in Proxmox
ssh root@192.168.0.37 "watch qm list"

# Once VMs are up, check cloud-init progress on server
# (Get IP from Proxmox web UI or wait for OpenTofu output)
ssh ubuntu@<server-ip> "tail -f /var/log/cloud-init-output.log"
```

## Step 8: Retrieve Kubeconfig

```bash
cd tofu
../scripts/get-kubeconfig.sh
```

This creates `./kubeconfig` with the cluster credentials.

Set it as your active config:

```bash
export KUBECONFIG=$(pwd)/kubeconfig
```

Verify cluster access:

```bash
kubectl get nodes -o wide
```

Expected output (wait until all nodes show `Ready`):
```
NAME                 STATUS   ROLES                  AGE   VERSION
k3s-server           Ready    control-plane,master   5m    v1.30.8+k3s1
k3s-worker-0         Ready    <none>                 3m    v1.30.8+k3s1
k3s-worker-1         Ready    <none>                 3m    v1.30.8+k3s1
k3s-gpu-worker-0     Ready    <none>                 3m    v1.30.8+k3s1
```

## Step 9: Label GPU Node

```bash
../scripts/label-gpu-node.sh
```

Verify:

```bash
kubectl get nodes --show-labels | grep accelerator
```

## Step 10: Deploy NVIDIA Device Plugin

```bash
../scripts/deploy-gpu-plugin.sh
```

Wait for pods to be ready (script will wait automatically).

Verify GPU is advertised:

```bash
kubectl get nodes -o json | \
  jq '.items[] | select(.status.capacity."nvidia.com/gpu") | {name: .metadata.name, gpu: .status.capacity."nvidia.com/gpu"}'
```

Expected output:
```json
{
  "name": "k3s-gpu-worker-0",
  "gpu": "1"
}
```

## Step 11: Test GPU

```bash
../scripts/test-gpu.sh
```

You should see nvidia-smi output showing your NVIDIA GeForce RTX 5060 Ti!

Example output:
```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.105.08             Driver Version: 580.105.08     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 5060 Ti     Off |   00000000:00:10.0 Off |                  N/A |
...
```

## Step 12: Deploy Your First GPU Workload

Create a test deployment:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-test
  template:
    metadata:
      labels:
        app: gpu-test
    spec:
      containers:
      - name: cuda-container
        image: nvidia/cuda:12.6.3-base-ubuntu24.04
        command: ["sleep", "infinity"]
        resources:
          limits:
            nvidia.com/gpu: 1
      nodeSelector:
        accelerator: nvidia
EOF
```

Verify it's running on the GPU node:

```bash
kubectl get pods -o wide
```

Test GPU access inside the pod:

```bash
kubectl exec -it deploy/gpu-test -- nvidia-smi
```

## Troubleshooting

### VMs not getting IPs

- Check DHCP server is running on your network
- Verify bridge `vmbr0` is configured correctly in Proxmox
- Wait longer - DHCP can take 30-60 seconds

### K3s server won't start

```bash
ssh ubuntu@<server-ip>
sudo journalctl -u k3s -f
```

Common issues:
- Port 6443 in use (check with `sudo netstat -tlnp | grep 6443`)
- Insufficient memory (check with `free -h`)

### Workers won't join

```bash
ssh ubuntu@<worker-ip>
tail -f /var/log/bootstrap-k3s-worker.log
```

Common issues:
- Can't reach server (test with `curl -k https://<server-ip>:6443/ping`)
- Wrong join token (retrieve manually from server and compare)

### GPU not visible in VM

```bash
ssh ubuntu@<gpu-worker-ip>
lspci | grep -i nvidia
```

If no output:
- Verify PCI ID is correct in `lab.tfvars`
- Check GPU is passed through: `ssh root@192.168.0.37 "qm config <vmid> | grep hostpci"`
- Verify IOMMU groups: `ssh root@192.168.0.37 "find /sys/kernel/iommu_groups/ -type l"`

### nvidia-smi not found

```bash
ssh ubuntu@<gpu-worker-ip>
tail -f /var/log/bootstrap-gpu-worker.log
```

Look for driver installation errors. Common issues:
- DKMS build failed (missing kernel headers)
- Wrong driver version (check `apt-cache policy nvidia-utils-580`)

## Next Steps

Now that your cluster is running:

1. **Install your ML framework** (PyTorch, TensorFlow, etc.)
2. **Deploy a model server** (vLLM, Ollama, TensorRT-LLM)
3. **Set up monitoring** (Prometheus + Grafana)
4. **Add persistent storage** (Longhorn, NFS)
5. **Configure backups** (Velero)

## Cleanup

To destroy the entire cluster:

```bash
cd tofu
tofu destroy -var-file=env/lab.tfvars
```

Type `yes` when prompted. All VMs will be deleted.

## Summary

You now have:
- ✅ 4-node K3s cluster
- ✅ 1 GPU worker with NVIDIA RTX 5060 Ti
- ✅ NVIDIA device plugin deployed
- ✅ GPU available to workloads via `nvidia.com/gpu` resource
- ✅ Node affinity for GPU workload scheduling

Happy clustering! 🎮🚀

