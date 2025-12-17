# Ubuntu 24.04 LTS Cloud-Init Template Setup for Proxmox

This guide walks through creating an Ubuntu 24.04 LTS cloud-init template on your Proxmox node.

## Prerequisites

- SSH access to your Proxmox node
- At least 10GB free space in your storage pool
- Ubuntu 24.04 cloud image (downloaded automatically in steps below)

## Steps

### 1. SSH into your Proxmox node

```bash
ssh root@192.168.0.37
```

### 2. Download Ubuntu 24.04 LTS cloud image

```bash
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

### 3. Create a new VM for the template

```bash
# VM ID 9000 (adjust if needed)
VM_ID=9000

qm create $VM_ID \
  --name ubuntu-2404-cloud-init \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci
```

### 4. Import the cloud image as a disk

```bash
qm importdisk $VM_ID \
  /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img \
  local-lvm
```

### 5. Attach the imported disk to the VM

```bash
# The import creates an unused disk, typically disk 0
qm set $VM_ID --scsi0 local-lvm:vm-$VM_ID-disk-0
```

### 6. Add a cloud-init drive

```bash
qm set $VM_ID --ide2 local-lvm:cloudinit
```

### 7. Configure boot disk and boot order

```bash
qm set $VM_ID --boot c --bootdisk scsi0
```

### 8. Add serial console (helpful for debugging)

```bash
qm set $VM_ID --serial0 socket --vga serial0
```

### 9. Enable QEMU guest agent

```bash
qm set $VM_ID --agent enabled=1
```

### 10. Set machine type to Q35 (important for GPU passthrough)

```bash
qm set $VM_ID --machine q35
```

### 11. Set BIOS to OVMF (UEFI)

```bash
# First, create an EFI disk
qm set $VM_ID --efidisk0 local-lvm:1,format=raw

# Set BIOS to OVMF
qm set $VM_ID --bios ovmf
```

### 12. Optional: Disable Secure Boot (recommended for GPU passthrough)

If you want unattended provisioning with GPU nodes:

```bash
# Edit the VM config file
nano /etc/pve/qemu-server/$VM_ID.conf

# Add or modify this line:
# bios: ovmf
# efidisk0: local-lvm:vm-9000-disk-1,efitype=4m,size=1M
```

For unattended GPU driver installation, it's easiest to disable Secure Boot or pre-enroll keys.

### 13. Convert to template

```bash
qm template $VM_ID
```

### 14. Verify template creation

```bash
qm list | grep $VM_ID
```

You should see your template listed with the name `ubuntu-2404-cloud-init`.

## Using the Template

In your `lab.tfvars` file, set:

```hcl
ubuntu_template_id = "9000"
```

Or use whatever VM ID you chose in step 3.

## Updating the Template

To update the template with a newer Ubuntu image:

1. Clone the template to a new VM
2. Boot it, update packages, make changes
3. Shut down the VM
4. Convert it to a new template
5. Update your `ubuntu_template_id` variable

## Troubleshooting

### Cloud-init not working

- Verify the cloud-init drive is attached: `qm config $VM_ID | grep ide2`
- Check that QEMU guest agent is enabled: `qm config $VM_ID | grep agent`

### VMs won't boot

- Check BIOS setting: `qm config $VM_ID | grep bios`
- Verify boot disk: `qm config $VM_ID | grep boot`

### GPU passthrough issues

- Ensure machine type is q35: `qm config $VM_ID | grep machine`
- Verify IOMMU is enabled on the Proxmox host: `dmesg | grep -e DMAR -e IOMMU`
- Check GPU PCI ID: `lspci -nn | grep -i nvidia`

## Next Steps

Once your template is created, proceed to:
1. Configure your `tofu/env/lab.tfvars` file
2. Run `tofu init` and `tofu apply`

