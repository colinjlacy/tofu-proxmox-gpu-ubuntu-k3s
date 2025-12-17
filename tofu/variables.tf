variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g., https://192.168.0.37:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for self-signed certificates"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "nuc"
}


variable "vm_network_bridge" {
  description = "Network bridge for VMs"
  type        = string
  default     = "vmbr0"
}

variable "vm_storage" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_size_gb" {
  description = "Default disk size for all VMs in GB"
  type        = number
  default     = 30
}

variable "name_prefix" {
  description = "Prefix for VM names"
  type        = string
  default     = "k3s"
}

variable "ssh_public_keys" {
  description = "List of SSH public keys for VM access"
  type        = list(string)
}

variable "k3s_version" {
  description = "K3s version to install"
  type        = string
  default     = "v1.34.2+k3s1"
}

variable "nvidia_driver_version" {
  description = "NVIDIA driver version (must be 580.105.08 or higher)"
  type        = string
  default     = "580"
}

variable "server_cores" {
  description = "CPU cores for K3s server node"
  type        = number
  default     = 4
}

variable "server_memory_mb" {
  description = "Memory in MB for K3s server node"
  type        = number
  default     = 4096
}

variable "worker_cores" {
  description = "CPU cores for non-GPU worker nodes"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "Memory in MB for non-GPU worker nodes"
  type        = number
  default     = 4096
}

variable "gpu_worker_cores" {
  description = "CPU cores for GPU worker node"
  type        = number
  default     = 4
}

variable "gpu_worker_memory_mb" {
  description = "Memory in MB for GPU worker node"
  type        = number
  default     = 16384
}

variable "gpu_pci_id" {
  description = "PCI ID of the GPU to pass through (e.g., 00000000:00:10.0)"
  type        = string
  default     = "00000000:00:10.0"
}

variable "worker_count" {
  description = "Number of non-GPU worker nodes"
  type        = number
  default     = 2
}

