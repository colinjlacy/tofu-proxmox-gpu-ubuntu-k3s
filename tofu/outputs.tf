output "k3s_server_ip" {
  description = "IP address of the K3s server node"
  value       = module.k3s_server.vm_ip
}

output "k3s_server_url" {
  description = "K3s server URL for joining workers"
  value       = module.k3s_server.server_url
}

output "k3s_token" {
  description = "K3s cluster token"
  value       = random_password.k3s_token.result
  sensitive   = true
}

output "worker_ips" {
  description = "IP addresses of non-GPU worker nodes"
  value       = [for w in module.k3s_workers : w.vm_ip]
}

output "gpu_worker_ip" {
  description = "IP address of GPU worker node"
  value       = module.k3s_gpu_worker.vm_ip
}

output "next_steps" {
  description = "Next steps to complete cluster setup"
  value = <<-EOT
    
    Cluster provisioned successfully!
    
    Next steps:
    1. Wait for all nodes to boot and complete cloud-init (5-10 minutes)
    
    2. Retrieve kubeconfig:
       ./scripts/get-kubeconfig.sh
       export KUBECONFIG=$(pwd)/kubeconfig
    
    3. Verify all nodes joined:
       kubectl get nodes -o wide
    
    4. Label and configure GPU node:
       ./scripts/label-gpu-node.sh
       ./scripts/deploy-gpu-plugin.sh
    
    5. Test GPU:
       ./scripts/test-gpu.sh
    
    Note: K3s cluster token is managed by OpenTofu and passed to all nodes.
    To view: tofu output -raw k3s_token
  EOT
}

