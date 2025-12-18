variable "name_prefix" {
  description = "Prefix for VM name"
  type        = string
}

variable "worker_index" {
  description = "Worker index number"
  type        = number
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "cloud_image_id" {
  description = "Cloud image file ID"
  type        = string
}

variable "vm_network_bridge" {
  description = "Network bridge"
  type        = string
}

variable "vm_storage" {
  description = "Storage pool for VM disks"
  type        = string
}

variable "vm_disk_size_gb" {
  description = "Disk size in GB"
  type        = number
}

variable "ssh_public_keys" {
  description = "SSH public keys"
  type        = list(string)
}

variable "ubuntu_password" {
  description = "Password for ubuntu user"
  type        = string
  sensitive   = true
}

variable "gpu_pci_id" {
  description = "GPU PCI ID to pass through"
  type        = string
}

variable "gpu_all_functions" {
  description = "Pass through all functions of the GPU device"
  type        = bool
  default     = true
}

variable "k3s_server_url" {
  description = "K3s server URL"
  type        = string
}

variable "k3s_token" {
  description = "K3s cluster token"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  description = "K3s version"
  type        = string
}

variable "nvidia_driver_version" {
  description = "NVIDIA driver version (e.g., '580' for 580.x series)"
  type        = string
}

variable "cores" {
  description = "CPU cores"
  type        = number
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
}

