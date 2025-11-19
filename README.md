# Legion - Sandboxed Development Environments for AI Tools

Legion is a sandbox and egress filtering utility for macOS designed specifically for AI coding assistants like Claude Code. It provides isolated development environments that run without constant permission checks while preventing access to internal networks and sensitive resources.

Built on years of experience with Kata Containers and microVM technologies, Legion uses a custom kernel and rootfs to achieve fast boot times (~2-3 seconds) while maintaining strong isolation guarantees. Each project gets its own ephemeral VM with controlled network access via egress filtering policies.

**Why Legion?**
- 🛡️ **Security**: Run AI tools without exposing internal networks or host resources
- 🚫 **Network isolation**: Egress filtering prevents access to private subnets and metadata services
- ⚡ **Fast**: Boot times of ~2-3 seconds (kernel: 117ms, userspace: ~2s, cloud-init: ~1s)
- 🔒 **Sandboxed**: Each project runs in its own isolated VM
- 🤖 **AI-optimized**: Pre-configured for Claude Code with minimal permission prompts
- 🔧 **Customizable**: Network policies, rootfs contents, and Lima VM configuration are all modifiable

**Customization**

Legion is designed to be highly customizable for different security and development requirements:
- **Network policy** (`policy.yaml`): Define egress filtering rules, allowed/blocked domains, IP ranges, and protocols
- **Rootfs contents** (`build-rootfs/`): Customize the base image with your own tools, packages, and configurations
- **VM configuration** (`legion.yaml`): Adjust CPU, memory, mounts, provisioning scripts, and Lima microVM capabilities

## Features

- ⚡ **Fast boot**: Direct kernel boot with no initrd
- 🔧 **Project-specific VMs**: Automatic VM per project directory
- 🐳 **Docker included**: Pre-configured Docker daemon
- 📦 **Claude Code ready**: Pre-installed with npm globals configured
- 🔒 **Isolated networking**: Custom network with egress filtering support
- 🔄 **Auto-cleanup**: VMs cleaned up on exit unless already running
- 📁 **Workspace mounting**: Project directory automatically mounted to `/workspace`
- 🐛 **Debug mode**: Optional `--debug` flag shows VM lifecycle and timing info

## Installation

### Build Prerequisites
- macOS with Apple Silicon (ARM64)
- Lima's docker VM running (`limactl start docker`)
- Make

### Build and Install

```bash
# Clone the repository
git clone <repo-url>
cd legion

# Build all components
make build-kernel build-rootfs build-limactl

# Install legion commands globally (optional)
make install-legion
```

After installation, you can run `legion` and `legion-limactl` from any directory.

### Uninstall

```bash
make uninstall-legion
```

## Quick Start

```bash
# From any project directory (if installed globally):
legion

# Or using the script directly:
./legion.sh

# This creates a project-specific VM and opens a shell
# VM name: legion-<projectname>_<hash>
# Workspace: current directory mounted to /workspace

# Run a command:
legion echo "hello from VM"

# The VM is automatically cleaned up when the command completes

# Debug mode (show timing and status):
legion --debug

# Shell into running VM from another terminal:
legion shell
```

## Components

### Core Files
- `legion.yaml` - Lima template configuration (source of truth)
- `legion.sh` - VM lifecycle management wrapper
- `policy.yaml` - Network policy for legion network
- `user-provision.sh` - User-mode provision script for Claude setup

### Build Directories
- `build-kernel/` - Custom Kata kernel 6.12.52 with vsock + ISO9660 support
- `build-rootfs/` - Custom Ubuntu 24.04 rootfs with dev tools
  - `Dockerfile.claude` - Node.js + Claude Code base image
  - `Dockerfile.disk` - Bootable disk image builder
  - `configure-rootfs.sh` - System configuration (networking, cloud-init, etc.)
  - `create-disk-image.sh` - Disk image creation from rootfs

### Output Artifacts
- `_output/legion-vmlinux` - Custom kernel (15MB uncompressed)
- `_output/legion-rootfs.img` - Bootable disk image (1.5GB)
- `_output/bin/legion-limactl` - Custom limactl with egress filtering (PR #4326)
- `_output/share/lima/lima-guestagent.Linux-aarch64.gz` - Guest agent (14MB)

## Architecture

### VM Configuration
- **VM Type**: vz (macOS Virtualization.framework)
- **Architecture**: aarch64 (ARM64)
- **Kernel**: Kata Containers 6.12.52
  - Built-in virtio, ext4, ISO9660, vsock support
  - Uncompressed vmlinux for fast loading
- **Boot Method**: Direct kernel boot (no bootloader, no initrd)
- **Root Filesystem**: Custom ext4 on /dev/vda1
- **Networking**: Custom "legion" network with usernet forwarding

### Rootfs Contents
Base image (legion-claude):
- Node.js 24 (slim)
- Claude Code CLI + DevContainers CLI
- Development tools: git, vim, docker.io, gh, jq, ripgrep, fzf
- Build tools: build-essential, python3
- Network tools: curl, wget, iputils-ping, dnsutils, iproute2, socat, lsof
- Monitoring: htop, btop

System packages (added in disk builder):
- systemd + systemd-resolved + libpam-systemd
- cloud-init + cloud-guest-utils
- openssh-server
- udev + kmod

Total disk usage: ~1.2GB of 1.5GB allocated

### Optimizations

1. **Direct kernel boot**: No initrd overhead
2. **Uncompressed kernel**: vmlinux loads faster than compressed Image.gz
3. **Minimal cloud-init**: Optimized modules, NoCloud datasource
4. **Disabled services**: networkd-wait-online, snapd, etc. masked
5. **Pre-configured npm**: Global prefix set to /usr/local/share/npm-global
6. **User sessions**: libpam-systemd enables systemd user mode
7. **Vsock fallback**: Falls back to usernet when vsock SSH fails

### VM Lifecycle

1. **Creation** (first run from directory):
   - Generates VM name from project directory hash
   - Creates legion network if needed
   - Starts VM with workspace mount
   - Runs system provision (Docker setup, permissions)
   - Runs user provision (Claude configuration)

2. **Subsequent runs**:
   - Checks if VM already running
   - If running: reuses existing VM
   - If stopped: starts existing VM
   - If missing: creates new VM

3. **Cleanup**:
   - Only stops/deletes VM if created in this session
   - Preserves running VMs across invocations

## Building

### Build Individual Components
```bash
# Custom kernel (~5 min)
make build-kernel

# Rootfs image (~2 min)
make build-rootfs

# Custom limactl (~1 min)
make build-limactl
```

## Provision Scripts

### System Provision (root)
```bash
# Runs once during VM creation
- Sets ownership of /usr/local/share to user
- Creates docker group
- Adds user to docker group
- Starts dockerd in background
```

### User Provision (user)
```bash
# Runs once during VM creation
- Creates ~/.claude directory
- Copies .claude.json from ~/.legion/.init if exists
- Merges defaults from ~/.legion/.defaults
- Sets up credential symlinks
- Handles initialization vs normal mode
```

## Directory Structure

```
~/.legion/
  .init/              # Initial configuration (writable)
    .claude.json      # Claude config (created on first run)
  .defaults/          # Default files to merge (read-only)
  .credentials/       # Credential storage (writable)
    .credentials.json # Claude credentials
  <project>_<hash>/   # Per-project VM instance data
```

## Networking

- **Network**: legion (custom Lima network)
- **Mode**: shared
- **Gateway**: 192.168.123.1/24
- **SSH**: Falls back to usernet when vsock fails
- **DNS**: systemd-resolved with host resolver
- **mDNS**: Enabled for .local resolution

## Known Issues

1. **Vsock SSH fails**: Connection refused on vsock port
   - **Workaround**: Automatically falls back to usernet forwarding
   - **Impact**: SSH works but uses network instead of vsock
   - **Cause**: Kernel or VZ configuration issue

2. **Initial hang after reboot**: VMs may fail to start after macOS reboot
   - **Workaround**: Reboot macOS again to clear stuck state
   - **Impact**: One-time delay after macOS reboot
   - **Cause**: macOS Virtualization.framework state issue

## Performance

| Metric | Time |
|--------|------|
| Kernel boot | 117ms |
| Userspace init | ~2s |
| Cloud-init | ~1s |
| **Total boot** | **~2-3s** |
| SSH ready | ~3s |

Compared to standard Ubuntu cloud image: ~3x faster

## Advanced Usage

### Accessing Different Directories
```bash
# Each directory gets its own VM
cd ~/project1
./path/to/legion/legion.sh  # Creates legion-project1_<hash>

cd ~/project2
./path/to/legion/legion.sh  # Creates legion-project2_<hash>
```

### Keeping VMs Running
```bash
# Start VM and keep it running
./legion.sh sleep infinity &

# Use from another terminal
./legion.sh shell
```

### Manual VM Management
```bash
# List VMs
_output/bin/legion-limactl list

# Stop specific VM
_output/bin/legion-limactl stop legion-<name>

# Delete specific VM
_output/bin/legion-limactl delete legion-<name>

# Delete all legion VMs
_output/bin/legion-limactl list | grep legion | awk '{print $1}' | xargs -n1 _output/bin/legion-limactl delete
```

## Development

### Modifying Rootfs
1. Edit `build-rootfs/Dockerfile.claude` for base image changes
2. Edit `build-rootfs/Dockerfile.disk` for system packages
3. Edit `build-rootfs/configure-rootfs.sh` for system configuration
4. Run `make build-rootfs`

### Modifying Kernel
1. Edit `build-kernel/.config` or `build-kernel/extras.conf`
2. Run `make build-kernel`

### Modifying Provision
1. Edit system provision in `legion.yaml`
2. Edit user provision in `user-provision.sh`
3. Recreate VM to see changes

## Credits

- **Lima**: Linux virtual machines on macOS - https://github.com/lima-vm/lima
- **Kata Containers**: Lightweight kernel - https://github.com/kata-containers/kata-containers
- **Cloud-init**: VM initialization - https://cloud-init.io/
- **Egress filtering PR**: Custom limactl build - https://github.com/lima-vm/lima/pull/4326
