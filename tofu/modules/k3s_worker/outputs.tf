output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.k3s_worker.id
}

output "vm_ip" {
  description = "VM IP address"
  value       = try(
    proxmox_virtual_environment_vm.k3s_worker.ipv4_addresses[1][0],
    proxmox_virtual_environment_vm.k3s_worker.ipv4_addresses[0][0],
    "IP not available - check VM"
  )
}

