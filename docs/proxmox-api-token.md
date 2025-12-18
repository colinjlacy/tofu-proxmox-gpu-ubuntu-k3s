# Creating a Proxmox API Token

This guide shows how to create an API token for OpenTofu to interact with Proxmox.

## Via Proxmox Web UI

1. Log into Proxmox web interface at `https://192.168.0.37:8006`

2. Navigate to **Datacenter → Permissions → API Tokens**

3. Click **Add** button

4. Fill in the form:
   - **User**: Select your user (e.g., `root@pam`)
   - **Token ID**: Give it a name (e.g., `tofu`)
   - **Privilege Separation**: **UNCHECK THIS BOX** (required for PCI passthrough)

5. Click **Add**

6. **IMPORTANT**: Copy the secret immediately - it will only be shown once!

   Your token will look like:
   ```
   root@pam!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

## Required Permissions

If you enabled privilege separation, the token needs these permissions:

- VM.Allocate
- VM.Audit
- VM.Clone
- VM.Config.CDROM
- VM.Config.CPU
- VM.Config.Cloudinit
- VM.Config.Disk
- VM.Config.HWType
- VM.Config.Memory
- VM.Config.Network
- VM.Config.Options
- Datastore.Allocate
- Datastore.AllocateSpace
- SDN.Use

For simplicity in a lab environment, you can grant Administrator permissions to the token.

## Via CLI (Recommended)

SSH into your Proxmox node:

```bash
ssh root@192.168.0.37
```

Create the token **without privilege separation** (required for GPU passthrough):

```bash
pveum user token add root@pam tofu --privsep 0
```

This will output the token secret. Copy it immediately.

**Important**: The `--privsep 0` flag is critical for PCI device passthrough to work.

## Using the Token in OpenTofu

In your `tofu/env/lab.tfvars` file:

```hcl
proxmox_api_token = "root@pam!tofu=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

## Security Notes

- Store the token securely
- Never commit the token to version control (it's in `.gitignore`)
- For GPU passthrough, privilege separation **must** be disabled (`--privsep 0`)
- For production without GPU passthrough, use privilege separation and grant minimal permissions
- Consider using environment variables: `export TF_VAR_proxmox_api_token="..."`

## Troubleshooting

### Error: "only root can set 'hostpci0' config for non-mapped devices"

This means your API token has privilege separation enabled. Fix with:

```bash
ssh root@192.168.0.37
pveum user token remove root@pam tofu
pveum user token add root@pam tofu --privsep 0
# Update your lab.tfvars with the new token
```

