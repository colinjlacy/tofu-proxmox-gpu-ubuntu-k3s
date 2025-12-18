output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.k3s_server.id
}

output "vm_ip" {
  description = "VM IP address"
  value       = try(
    proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[1][0],
    proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[0][0],
    "IP not available - check VM"
  )
}

output "server_url" {
  description = "K3s server URL"
  value       = "https://${try(
    proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[1][0],
    proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[0][0],
    "IP_NOT_AVAILABLE"
  )}:6443"
}

