#!/bin/bash
set -euo pipefail

# Create disk image with partition and filesystem for Legion VM
# This script creates a disk image with a partitioned ext4 filesystem
#
# Usage: create-disk-image.sh <rootfs_dir> <output_image>
#
# Arguments:
#   rootfs_dir   - Directory containing the rootfs to package (default: /rootfs)
#   output_image - Output disk image path (default: /legion-rootfs.img)
#
# Sizing:
#   Partition size = rootfs_size + 20% overhead (10% ext4 metadata, 10% safety)
#   Disk size = partition_size + 20MB (partition table overhead)

ROOTFS="${1:-/rootfs}"
OUTPUT="${2:-/legion-rootfs.img}"
OVERHEAD_PERCENT=20  # 10% for ext4 metadata/reserved blocks, 10% for safety margin

# Calculate actual rootfs size
echo "==> Calculating rootfs size..."
ROOTFS_SIZE_KB=$(du -sk "$ROOTFS" | cut -f1)
ROOTFS_SIZE_MB=$((ROOTFS_SIZE_KB / 1024))
echo "    Rootfs size: ${ROOTFS_SIZE_MB}MB"
echo "    Overhead: ${OVERHEAD_PERCENT}% (ext4 + safety margin)"

# Calculate partition and disk sizes with overhead
OVERHEAD_MB=$((ROOTFS_SIZE_MB * OVERHEAD_PERCENT / 100))
PARTITION_SIZE_MB=$((ROOTFS_SIZE_MB + OVERHEAD_MB))
DISK_SIZE_MB=$((PARTITION_SIZE_MB + 20))

echo "==> Creating disk image (${DISK_SIZE_MB}MB total, ${PARTITION_SIZE_MB}MB filesystem)..."

# Create empty disk image
dd if=/dev/zero of="$OUTPUT" bs=1M count=$DISK_SIZE_MB

echo "==> Creating partition table..."
# Create DOS partition table with one primary partition
# o = create new DOS partition table
# n = new partition
# p = primary
# 1 = partition number
# (defaults for start/end)
# a = toggle bootable flag
# w = write changes
echo -e "o\nn\np\n1\n\n\na\nw\n" | fdisk "$OUTPUT"

echo "==> Creating ext4 filesystem with rootfs contents..."
# Calculate partition offset (sector 2048 * 512 bytes = 1048576 bytes = 1M)
# Create filesystem on separate image first, then write to partition
dd if=/dev/zero of=/partition.ext4 bs=1M count=$PARTITION_SIZE_MB
mkfs.ext4 -F -d "$ROOTFS" /partition.ext4

# Verify filesystem is not full
echo "==> Verifying filesystem has free space..."
read USAGE FREE TOTAL < <(tune2fs -l /partition.ext4 | awk '/^Block count:/{bc=$NF} /^Free blocks:/{fb=$NF} END{printf "%d %d %d\n", (bc-fb)*100/bc, fb, bc}')
[ $USAGE -ge 95 ] && { echo "ERROR: Filesystem is ${USAGE}% full! Increase OVERHEAD_PERCENT."; exit 1; }
echo "    Filesystem usage: ${USAGE}% (${FREE}/${TOTAL} blocks free)"

echo "==> Writing filesystem to partition..."
# Write the filesystem to the partition offset (skip first 1M for partition table)
dd if=/partition.ext4 of="$OUTPUT" bs=1M seek=1 conv=notrunc

echo "==> Cleaning up temporary files..."
rm -f /partition.ext4

echo "==> Disk image created successfully: $OUTPUT"
ls -lh "$OUTPUT"
