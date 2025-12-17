# Troubleshooting Guide

## OpenTofu Issues

### Error: Failed to create VM

**Symptom**: OpenTofu fails with "template not found" or similar error

**Solution**:
- Verify template exists: `ssh root@192.168.0.37 "qm list | grep 9000"`
- Check template ID in `lab.tfvars` matches your actual template ID
- Ensure template is actually a template: `qm config 9000 | grep template`

### Error: API authentication failed

**Symptom**: `401 Unauthorized` or `authentication failed`

**Solution**:
- Verify API token format: `user@realm!tokenid=secret`
- Check token permissions in Proxmox UI
- Test token manually:
  ```bash
  curl -k -H "Authorization: PVEAPIToken=root@pam!tofu=xxx" \
    https://192.168.0.37:8006/api2/json/nodes
  ```

### VMs created but can't get IP addresses

**Symptom**: OpenTofu times out waiting for VM IP

**Solution**:
- Ensure QEMU guest agent is installed in template
- Verify VMs are actually booting: check Proxmox console
- Check DHCP server is running on your network
- Wait longer - first boot with cloud-init can take 3-5 minutes

## K3s Issues

### Server won't start

**Symptom**: K3s server fails to initialize

**Solution**:
- SSH to server: `ssh ubuntu@<server-ip>`
- Check logs: `sudo journalctl -u k3s -f`
- Check cloud-init: `tail -f /var/log/bootstrap-k3s-server.log`
- Verify ports 6443 and 443 are not in use

### Workers won't join

**Symptom**: Worker nodes don't appear in `kubectl get nodes`

**Solution**:
- SSH to worker: `ssh ubuntu@<worker-ip>`
- Check logs: `sudo journalctl -u k3s-agent -f`
- Check cloud-init: `tail -f /var/log/bootstrap-k3s-worker.log`
- Verify network connectivity to server: `curl -k https://<server-ip>:6443/ping`
- Check if join token is accessible on server: `ssh ubuntu@<server-ip> sudo cat /var/lib/rancher/k3s/server/node-token`

## GPU Issues

### nvidia-smi not found

**Symptom**: GPU worker bootstrap fails with "nvidia-smi: command not found"

**Solution**:
- SSH to GPU worker: `ssh ubuntu@<gpu-worker-ip>`
- Check driver installation: `tail -f /var/log/bootstrap-gpu-worker.log`
- Verify PCI device is visible: `lspci | grep -i nvidia`
- Check DKMS status: `dkms status`
- Try manual driver install:
  ```bash
  sudo apt update
  sudo apt install -y nvidia-dkms-580-open nvidia-utils-580
  sudo nvidia-smi
  ```

### GPU not visible in Kubernetes

**Symptom**: `kubectl describe node` doesn't show `nvidia.com/gpu` resource

**Solution**:
1. Verify NVIDIA device plugin is running:
   ```bash
   kubectl get pods -n nvidia-device-plugin
   ```

2. Check if node is labeled:
   ```bash
   kubectl get nodes --show-labels | grep accelerator
   ```

3. If not labeled, label it:
   ```bash
   kubectl label node k3s-gpu-worker-0 accelerator=nvidia
   ```

4. Check device plugin logs:
   ```bash
   kubectl logs -n nvidia-device-plugin -l name=nvidia-device-plugin-ds
   ```

5. Verify containerd runtime config:
   ```bash
   ssh ubuntu@<gpu-worker-ip>
   sudo cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml | grep nvidia
   ```

### GPU passthrough not working

**Symptom**: VM boots but GPU not visible with `lspci`

**Solution**:
- Check PCI ID is correct on Proxmox host:
  ```bash
  ssh root@192.168.0.37 "lspci | grep -i nvidia"
  ```
- Verify IOMMU is enabled:
  ```bash
  ssh root@192.168.0.37 "dmesg | grep -i iommu"
  ```
- Check VM config:
  ```bash
  ssh root@192.168.0.37 "qm config <vmid> | grep hostpci"
  ```
- Ensure machine type is q35 and BIOS is OVMF

### Driver version mismatch

**Symptom**: nvidia-smi shows wrong driver version or fails

**Solution**:
- The `nvidia_driver_version` variable specifies the driver series (e.g., "580")
- Ubuntu will install the latest patch version from that series (e.g., 580.105.08)
- To force a specific version:
  ```bash
  apt-cache policy nvidia-utils-580
  apt install nvidia-utils-580=580.105.08-0ubuntu1
  ```

## Cloud-Init Issues

### Cloud-init didn't run

**Symptom**: VMs boot but K3s isn't installed

**Solution**:
- SSH to VM
- Check cloud-init status: `cloud-init status`
- Check logs:
  ```bash
  sudo cat /var/log/cloud-init.log
  sudo cat /var/log/cloud-init-output.log
  ```
- Manually run cloud-init: `sudo cloud-init clean && sudo cloud-init init`

### Bootstrap script failed

**Symptom**: Cloud-init ran but custom bootstrap script failed

**Solution**:
- Check bootstrap logs:
  ```bash
  sudo tail -100 /var/log/bootstrap-*.log
  ```
- Check for marker file:
  ```bash
  ls -la /var/lib/bootstrap-*.ok
  ```
- Manually run script:
  ```bash
  sudo bash -x /usr/local/bin/bootstrap-*.sh
  ```

## Network Issues

### Can't access VMs via SSH

**Symptom**: SSH connection refused or times out

**Solution**:
- Verify VM has IP: check Proxmox console or `qm guest cmd <vmid> network-get-interfaces`
- Check firewall rules on your network
- Verify SSH key is correct: check against `https://github.com/colinjlacy.keys`
- Try from Proxmox host first: `ssh ubuntu@<vm-ip>`

### VMs can't reach internet

**Symptom**: Package installation fails in cloud-init

**Solution**:
- Check VM can reach gateway: `ssh ubuntu@<vm-ip> "ping 192.168.0.1"`
- Check DNS: `ssh ubuntu@<vm-ip> "ping 8.8.8.8"`
- Verify bridge configuration on Proxmox
- Check if firewall is blocking outbound traffic

## Getting Help

If issues persist:

1. Collect logs:
   ```bash
   # From each VM
   sudo tar czf ~/logs.tar.gz /var/log/cloud-init* /var/log/bootstrap-*
   ```

2. Check OpenTofu state:
   ```bash
   cd tofu
   tofu show
   ```

3. Verify Proxmox host health:
   ```bash
   ssh root@192.168.0.37
   pveversion
   pvesh get /cluster/resources
   ```

