#!/bin/bash
set -euo pipefail

# Configure rootfs for Legion VM
# This script configures systemd, networking, DNS, and cloud-init optimizations

ROOTFS="${1:-/rootfs}"
cd "$ROOTFS"

echo "==> Configuring systemd masks..."
# Configure systemd masks to disable unnecessary services
mkdir -p etc/systemd/system
ln -sf /dev/null etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null etc/systemd/system/snapd.service
ln -sf /dev/null etc/systemd/system/snapd.seeded.service
ln -sf /dev/null etc/systemd/system/pollinate.service
ln -sf /dev/null etc/systemd/system/ModemManager.service
ln -sf /dev/null etc/systemd/system/udisks2.service
ln -sf /dev/null etc/systemd/system/apport.service
ln -sf /dev/null etc/systemd/system/boot-efi.mount
ln -sf /dev/null etc/systemd/system/e2scrub_reap.service

echo "==> Setting up fstab..."
echo "/dev/vda1 / ext4 defaults 0 1" > etc/fstab

echo "==> Configuring networking..."
# Setup systemd-networkd configuration
mkdir -p etc/systemd/network
cat > etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

echo "==> Enabling systemd-networkd and systemd-resolved..."
# Enable systemd-networkd
ln -sf /usr/lib/systemd/system/systemd-networkd.service \
    etc/systemd/system/multi-user.target.wants/systemd-networkd.service

# Enable systemd-resolved
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
    etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /usr/lib/systemd/system/systemd-resolved.service \
    etc/systemd/system/dbus-org.freedesktop.resolve1.service

echo "==> Configuring DNS with systemd-resolved..."
# Symlink /etc/resolv.conf to systemd-resolved's stub (standard Ubuntu way)
# cloud-init and netplan will configure DNS dynamically through systemd-resolved
rm -f etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf etc/resolv.conf

echo "==> Creating /etc/hosts..."
# Create basic /etc/hosts file (Lima will add host.lima.internal dynamically)
cat > etc/hosts <<'EOF'
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
fe00::0		ip6-localnet
ff00::0		ip6-mcastprefix
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

echo "==> Optimizing cloud-init for faster boot..."
mkdir -p etc/cloud/cloud.cfg.d

# Specify NoCloud datasource directly (skip auto-detection)
echo "datasource_list: [ NoCloud ]" > etc/cloud/cloud.cfg.d/90_lima_datasource.cfg

# Optimize cloud-init modules for faster boot while keeping provision support
cat > etc/cloud/cloud.cfg.d/91_lima_optimize.cfg <<'EOF'
# Early boot modules
cloud_init_modules:
  - seed_random
  - write_files
  - growpart
  - resizefs
  - disk_setup
  - mounts
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - ca_certs
  - rsyslog
  - users_groups
  - ssh
  - set_passwords

# Mid-boot configuration modules (needed for Lima provision scripts)
cloud_config_modules:
  - runcmd

# Late boot modules for user scripts
cloud_final_modules:
  - scripts_vendor
  - scripts_per_once
  - scripts_per_boot
  - scripts_per_instance
  - scripts_user
  - ssh_authkey_fingerprints
  - keys_to_console
EOF

echo "==> Rootfs configuration complete!"
