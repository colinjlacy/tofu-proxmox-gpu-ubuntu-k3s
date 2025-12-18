resource "proxmox_virtual_environment_vm" "k3s_worker" {
  name        = "${var.name_prefix}-worker-${var.worker_index}"
  description = "K3s worker node"
  node_name   = var.proxmox_node

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.vm_storage
    interface    = "scsi0"
    size         = var.vm_disk_size_gb
    file_format  = "raw"
    import_from  = var.cloud_image_id
  }

  network_device {
    bridge = var.vm_network_bridge
  }

  agent {
    enabled = true
    timeout = "15m"
  }

  started = true

  operating_system {
    type = "l26"
  }

  serial_device {}

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = var.ssh_public_keys
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_worker.id
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_worker" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/cloudinit/user-data.yaml.tftpl", {
      k3s_server_url  = var.k3s_server_url
      k3s_token       = var.k3s_token
      k3s_version     = var.k3s_version
      ubuntu_password = var.ubuntu_password
      ssh_public_keys = var.ssh_public_keys
    })

    file_name = "${var.name_prefix}-worker-${var.worker_index}-cloud-init.yaml"
  }
}

