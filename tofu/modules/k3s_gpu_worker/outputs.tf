output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.k3s_gpu_worker.id
}

output "vm_ip" {
  description = "VM IP address"
  value       = proxmox_virtual_environment_vm.k3s_gpu_worker.ipv4_addresses[1][0]
}

output "gpu_pci_id" {
  description = "GPU PCI ID passed through to this worker"
  value       = var.gpu_pci_id
}

