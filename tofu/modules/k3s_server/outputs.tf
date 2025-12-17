output "vm_id" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.k3s_server.id
}

output "vm_ip" {
  description = "VM IP address"
  value       = proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[1][0]
}

output "server_url" {
  description = "K3s server URL"
  value       = "https://${proxmox_virtual_environment_vm.k3s_server.ipv4_addresses[1][0]}:6443"
}

