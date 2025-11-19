# Legion Kernel Builder

This directory contains the Dockerfile to build a custom Kata Containers kernel with additional features for Lima.

## What's customized

The kernel is based on **Kata Containers kernel 6.12.52** with these additions:

1. **ISO9660 filesystem support** - Required for cloud-init cidata mounting
2. **Built-in virtio drivers** - Allows direct boot without initrd
3. **Built-in ext4 support** - Allows direct boot without initrd

These additions are defined in `extras.conf` and appended to the Kata kernel config.

## Building the kernel

```bash
# Build using Docker
DOCKER_HOST="unix:///Users/$USER/.lima/docker/sock/docker.sock" \
  docker build -t legion-kernel-builder .

# Extract the kernel
DOCKER_HOST="unix:///Users/$USER/.lima/docker/sock/docker.sock" \
  docker save legion-kernel-builder:latest -o /tmp/legion-kernel.tar

# Extract legion-vmlinux
cd /tmp && rm -rf kernel-extract && mkdir kernel-extract && cd kernel-extract
tar -xf /tmp/legion-kernel.tar
tar -xzOf blobs/sha256/* > ~/git/lima/legion/legion-vmlinux
ls -lh ~/git/lima/legion/legion-vmlinux
```

## Why not use stock Kata kernel?

The stock Kata kernel doesn't include:
- ISO9660 support (needed for cloud-init cidata)
- Some features are modules instead of built-in (requiring initrd)

Our custom build ensures all necessary drivers are built-in, allowing for faster direct kernel boot without an initrd.

## Kernel size

The uncompressed kernel (legion-vmlinux) is approximately 15MB. We use the uncompressed version for faster boot times (no decompression overhead).
