# Download Ubuntu 24.04 cloud image
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}

# Generate K3s cluster token
resource "random_password" "k3s_token" {
  length  = 64
  special = false
}

# Generate ubuntu user password for console access (debugging)
resource "random_password" "ubuntu_password" {
  length  = 16
  special = true
}

# K3s Server (Control Plane)
module "k3s_server" {
  source = "./modules/k3s_server"

  name_prefix       = var.name_prefix
  proxmox_node      = var.proxmox_node
  cloud_image_id    = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  vm_network_bridge = var.vm_network_bridge
  vm_storage        = var.vm_storage
  vm_disk_size_gb   = var.vm_disk_size_gb

  ssh_public_keys = var.ssh_public_keys
  ubuntu_password = random_password.ubuntu_password.result
  k3s_version     = var.k3s_version
  k3s_token       = random_password.k3s_token.result

  cores     = var.server_cores
  memory_mb = var.server_memory_mb
}

# Non-GPU Worker Nodes
module "k3s_workers" {
  source = "./modules/k3s_worker"
  count  = var.worker_count

  name_prefix       = var.name_prefix
  worker_index      = count.index
  proxmox_node      = var.proxmox_node
  cloud_image_id    = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  vm_network_bridge = var.vm_network_bridge
  vm_storage        = var.vm_storage
  vm_disk_size_gb   = var.vm_disk_size_gb

  ssh_public_keys = var.ssh_public_keys
  ubuntu_password = random_password.ubuntu_password.result

  k3s_server_url = module.k3s_server.server_url
  k3s_token      = random_password.k3s_token.result
  k3s_version    = var.k3s_version

  cores     = var.worker_cores
  memory_mb = var.worker_memory_mb

  depends_on = [module.k3s_server]
}

# GPU Worker Node
module "k3s_gpu_worker" {
  source = "./modules/k3s_gpu_worker"

  name_prefix       = var.name_prefix
  worker_index      = 0
  proxmox_node      = var.proxmox_node
  cloud_image_id    = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  vm_network_bridge = var.vm_network_bridge
  vm_storage        = var.vm_storage
  vm_disk_size_gb   = var.vm_disk_size_gb

  ssh_public_keys = var.ssh_public_keys
  ubuntu_password = random_password.ubuntu_password.result

  gpu_pci_id        = var.gpu_pci_id
  gpu_all_functions = true

  k3s_server_url = module.k3s_server.server_url
  k3s_token      = random_password.k3s_token.result
  k3s_version    = var.k3s_version

  nvidia_driver_version = var.nvidia_driver_version

  cores     = var.gpu_worker_cores
  memory_mb = var.gpu_worker_memory_mb

  depends_on = [module.k3s_server]
}

