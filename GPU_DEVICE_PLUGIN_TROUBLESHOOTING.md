# NVIDIA Device Plugin Troubleshooting

## Problem Summary

The NVIDIA device plugin fails to advertise GPU resources (`nvidia.com/gpu`) to the Kubernetes cluster, despite the GPU being fully functional and accessible to containers. The plugin consistently reports "Incompatible strategy detected auto" and "No devices found."

## Environment Details

- **GPU**: NVIDIA GeForce RTX 5060 Ti (new GPU model, requires driver 580.105.08+)
- **Kubernetes**: K3s v1.34.2+k3s1
- **OS**: Ubuntu 24.04 LTS
- **NVIDIA Driver**: 580.95.05 (open kernel modules)
- **NVIDIA Container Toolkit**: 1.18.1
- **Device Plugin Versions Tested**: v0.17.0, v0.18.0

## Root Cause

The NVIDIA device plugin's auto-detection logic is incompatible with K3s's containerd configuration structure. The plugin validates the container runtime configuration before attempting to enumerate GPUs and rejects K3s's setup as incompatible.

Possible contributing factors:
1. The RTX 5060 Ti is a very new GPU model that may not be recognized by the device plugin's discovery routines
2. K3s uses a containerd configuration structure that differs from standard Kubernetes
3. The device plugin's runtime validation logic cannot parse K3s's configuration format

**Unable to determine exact cause** - the device plugin fails before providing detailed error messages about what specifically is incompatible.

## Verification: Direct GPU Access via RuntimeClass

A test pod was able to access the GPU hardware using RuntimeClass:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-smi-test-manual
spec:
  runtimeClassName: nvidia
  nodeSelector:
    accelerator: nvidia
  containers:
  - name: cuda
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["nvidia-smi"]
EOF
```

**Result**: The pod detected the RTX 5060 Ti and driver version 580.95.05. This confirms GPU hardware access works, but does not address the device plugin issue.

## Errors Encountered

### 1. Incompatible Strategy Detection
```
E1218 21:38:29.590783 1 factory.go:113] Incompatible strategy detected auto
E1218 21:38:29.590788 1 factory.go:114] If this is a GPU node, did you configure the NVIDIA Container Toolkit?
I1218 21:38:29.590798 1 main.go:385] No devices found. Waiting indefinitely.
```

### 2. Missing runc Dependency
```
level=error msg="failed to create NVIDIA Container Runtime: error constructing low-level runtime: 
error locating runtime: no runtime binary found from candidate list: [runc crun]"
```

**Fix**: Installed `runc` package system-wide (added to cloud-init).

### 3. Missing CDI Specs
```
time="2025-12-18T19:56:07Z" level=info msg="Found 0 CDI devices"
```

**Fix**: Added CDI spec generation to cloud-init bootstrap:
```bash
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

### 4. Invalid Device List Strategy
Attempted strategies that failed:
- `--device-list-strategy=nvml` → "invalid strategy: nvml"
- `--device-list-strategy=cdi` → "invalid strategy: cdi"
- `--device-list-strategy=volume-mounts` → Still reported "Incompatible strategy detected auto"

### 5. ConfigMap Parse Error
```
E1218 21:35:32.020938 1 main.go:177] error starting plugins: unable to load config: 
unable to finalize config: unable to parse config file: error parsing config file: 
unmarshal error: error unmarshaling JSON: while decoding JSON: no resources specified
```

Attempted to use a ConfigMap-based configuration file but the device plugin couldn't parse it correctly.

### 6. Library Conflict
When mounting `/usr/lib/x86_64-linux-gnu` for NVML access:
```
nvidia-device-plugin: symbol lookup error: /usr/lib/x86_64-linux-gnu/libc.so.6: 
undefined symbol: __tunable_is_initialized, version GLIBC_PRIVATE
```

**Fix**: Removed the library volume mount, allowing the device plugin to use its own libraries.

## Attempted Solutions

### 1. Runtime Configuration Modifications
- Created `config.toml.tmpl` for K3s containerd
- Added NVIDIA runtime to containerd configuration
- Used K3s drop-in config directory (`/var/lib/rancher/k3s/agent/etc/containerd/config.toml.d/`)
- Created RuntimeClass resource for `nvidia` handler

### 2. Device Plugin Configuration Variations
- Tested multiple device plugin versions
- Attempted explicit device list strategies
- Added CDI volume mounts
- Configured environment variables (CDI_ROOT, LD_LIBRARY_PATH, NVIDIA_DRIVER_CAPABILITIES)
- Tried ConfigMap-based configuration file

### 3. Installation Order Changes
- Ensured QEMU guest agent is installed
- Added `runc` to prerequisites
- Generated CDI specs during bootstrap
- Configured NVIDIA container toolkit before K3s agent installation

## Current Workaround: RuntimeClass-Based GPU Access

Without a functioning device plugin, GPU access must be achieved through Kubernetes RuntimeClass instead of standard resource requests.

### RuntimeClass Configuration

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
```

### Pod Configuration

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-gpu-workload
spec:
  runtimeClassName: nvidia  # Use NVIDIA runtime
  nodeSelector:
    accelerator: nvidia      # Manually target GPU node
  containers:
  - name: my-container
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    # Note: Cannot specify resource limits or requests for GPU
```

## RuntimeClass Approach Characteristics

### Limitations

1. **No Resource Limits**: Cannot limit GPU access to specific devices or fractions
2. **No Kubernetes Scheduling**: Scheduler doesn't see GPU as a resource for automatic placement decisions
3. **Manual Node Selection**: Must use nodeSelector to target GPU nodes
4. **No Multi-Tenancy**: All containers on the node can potentially access the GPU
5. **No Resource Accounting**: Kubernetes cannot track or report GPU usage
6. **Missing Standard API**: Does not follow Kubernetes device plugin framework conventions

### What Still Works

1. Containers can access GPU hardware directly
2. No device plugin deployment required
3. Works with K3s's default containerd configuration

## Cloud-Init Modifications

The GPU worker cloud-init was updated to fix prerequisite issues found during troubleshooting:

```yaml
# Install prerequisites including runc
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg dkms build-essential \
  linux-headers-$(uname -r) runc

# Install NVIDIA drivers (open kernel modules)
apt-get install -y --no-install-recommends \
  nvidia-driver-${nvidia_driver_version}-open

# Install NVIDIA container toolkit
apt-get install -y nvidia-container-toolkit

# Generate CDI specs for GPU discovery
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# Install K3s agent with pre-configured NVIDIA runtime
curl -sfL https://get.k3s.io | \
  K3S_URL="${k3s_server_url}" \
  K3S_TOKEN="${k3s_token}" \
  INSTALL_K3S_VERSION="${k3s_version}" \
  sh -
```

## Recommendations

### Next Steps to Resolve Device Plugin Issue

1. **Test with NVIDIA GPU Operator**: The GPU Operator is a more comprehensive solution that may handle K3s's containerd configuration better than the standalone device plugin
2. **Wait for Updated Device Plugin**: Monitor NVIDIA's device plugin releases for:
   - RTX 50-series GPU support
   - Improved K3s compatibility
3. **Test on Standard Kubernetes**: Deploy on a standard Kubernetes distribution to determine if this is K3s-specific
4. **Engage NVIDIA Support**: Open an issue with:
   - Hardware: RTX 5060 Ti
   - Driver: 580.95.05 (open kernel modules)
   - K3s version and containerd configuration
   - Device plugin logs showing "Incompatible strategy detected auto"

### For Production Use

The RuntimeClass workaround may be insufficient for production workloads that require:
- GPU resource limits and quotas
- Scheduler-aware GPU placement
- Multi-tenant GPU sharing
- Resource accounting and monitoring

## Status

**GPU Hardware Access**: ✅ Functional via RuntimeClass  
**Device Plugin**: ❌ Not Functional  
**Resource Limits/Scheduling**: ❌ Not Available  
**Issue**: Unresolved

