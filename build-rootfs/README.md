# Legion Rootfs Builder

This directory contains the Dockerfile to build the custom rootfs disk image for the Legion VM.

## Building the rootfs image

```bash
# Build the Docker image
DOCKER_HOST="unix:///Users/$USER/.lima/docker/sock/docker.sock" \
  docker build -f Dockerfile.disk -t legion-disk-builder .

# Extract the image (from the legion directory)
cd ..
DOCKER_HOST="unix:///Users/$USER/.lima/docker/sock/docker.sock" \
  docker save legion-disk-builder:latest -o /tmp/legion-disk-builder.tar

# Extract the disk image from the Docker layer
cd /tmp && rm -rf legion-extract && mkdir legion-extract && cd legion-extract
tar -xf /tmp/legion-disk-builder.tar
tar -xzOf blobs/sha256/* > ~/git/lima/legion/legion-rootfs.img
ls -lh ~/git/lima/legion/legion-rootfs.img
```

## What's included

The rootfs includes:
- systemd and udev
- cloud-init (for user/SSH setup)
- openssh-server
- Basic networking tools (iproute2, iputils-ping, curl)
- rsync (required by Lima boot scripts)
- Preserved apt cache for faster updates

## Image specifications

- Total size: 450MB raw disk image
- Filesystem: ext4 on /dev/vda1
- MBR partition table
- Actual usage: ~331MB
