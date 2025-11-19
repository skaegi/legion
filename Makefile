# Makefile for Legion VM
# Fast-booting Lima VM with custom kernel and rootfs

DOCKER_HOST := unix:///Users/$(USER)/.lima/docker/sock/docker.sock
LIMACTL := limactl
OUTPUT_DIR := _output
LEGION_LIMACTL := $(OUTPUT_DIR)/bin/legion-limactl

# Rootfs build parameters (can be overridden: make build-rootfs BASE_IMAGE=ubuntu:24.10)
BASE_IMAGE ?= ubuntu:24.04

.PHONY: all build-kernel build-rootfs build-limactl test start stop clean validate

all: build-rootfs

# Create output directory
$(OUTPUT_DIR):
	@mkdir -p $(OUTPUT_DIR)

# Build the custom kernel
build-kernel: $(OUTPUT_DIR)
	@echo "Building custom Kata kernel with ISO9660 support..."
	cd build-kernel && \
		DOCKER_HOST=$(DOCKER_HOST) docker build -t legion-kernel-builder .
	@echo "Extracting kernel..."
	DOCKER_HOST=$(DOCKER_HOST) docker create --name legion-kernel-extract legion-kernel-builder /legion-vmlinux
	DOCKER_HOST=$(DOCKER_HOST) docker cp legion-kernel-extract:/legion-vmlinux $(OUTPUT_DIR)/legion-vmlinux
	DOCKER_HOST=$(DOCKER_HOST) docker rm legion-kernel-extract
	@ls -lh $(OUTPUT_DIR)/legion-vmlinux
	@echo "Done! Kernel created: $(OUTPUT_DIR)/legion-vmlinux"

# Build the custom rootfs disk image
build-rootfs: $(OUTPUT_DIR)
	@echo "Building legion-claude base image..."
	cd build-rootfs && \
		DOCKER_HOST=$(DOCKER_HOST) docker build \
		-f Dockerfile.claude -t legion-claude:latest .
	@echo "Building custom rootfs disk image..."
	@echo "  BASE_IMAGE=legion-claude:latest"
	@echo "  Partition size: rootfs + 100MB headroom (automatic)"
	cd build-rootfs && \
		DOCKER_HOST=$(DOCKER_HOST) docker build \
		--build-arg BASE_IMAGE=legion-claude:latest \
		-f Dockerfile.disk -t legion-disk-builder .
	@echo "Extracting disk image..."
	DOCKER_HOST=$(DOCKER_HOST) docker create --name legion-disk-extract legion-disk-builder /legion-rootfs.img
	DOCKER_HOST=$(DOCKER_HOST) docker cp legion-disk-extract:/legion-rootfs.img $(OUTPUT_DIR)/legion-rootfs.img
	DOCKER_HOST=$(DOCKER_HOST) docker rm legion-disk-extract
	@ls -lh $(OUTPUT_DIR)/legion-rootfs.img
	@echo "Done! Rootfs image created: $(OUTPUT_DIR)/legion-rootfs.img"

# Build custom limactl with egress filtering (native macOS build)
build-limactl: $(OUTPUT_DIR)
	@echo "Building custom limactl and guestagent from PR #4326 (egress-filter)..."
	@echo "Cloning Lima repository..."
	rm -rf /tmp/lima-build
	cd /tmp && git clone https://github.com/lima-vm/lima.git lima-build
	cd /tmp/lima-build && \
		git fetch origin pull/4326/head:egress-filter && \
		git checkout egress-filter
	@echo "Building limactl and guestagent..."
	cd /tmp/lima-build && make limactl native-guestagent
	@echo "Copying binaries..."
	mkdir -p $(OUTPUT_DIR)/bin
	cp /tmp/lima-build/_output/bin/limactl $(OUTPUT_DIR)/bin/legion-limactl
	chmod +x $(OUTPUT_DIR)/bin/legion-limactl
	@echo "Setting up guestagent..."
	mkdir -p $(OUTPUT_DIR)/share/lima
	cp /tmp/lima-build/_output/share/lima/lima-guestagent.Linux-*.gz $(OUTPUT_DIR)/share/lima/
	@ls -lh $(OUTPUT_DIR)/bin/legion-limactl $(OUTPUT_DIR)/share/lima/
	@echo "Done! Custom limactl and guestagent created"

# Validate the Lima template
validate:
	$(LIMACTL) validate legion.yaml

# Start the VM
start: validate build-limactl
	@echo "Starting Legion VM..."
	time $(LEGION_LIMACTL) start legion.yaml

# Stop the VM
stop:
	$(LEGION_LIMACTL) stop legion

# Shell into the VM
shell:
	$(LEGION_LIMACTL) shell legion

# Test the VM (start, check boot time, show systemd-analyze)
test: start
	@echo ""
	@echo "=== Systemd Boot Analysis ==="
	$(LEGION_LIMACTL) shell legion sudo systemd-analyze
	@echo ""
	@echo "=== Slowest Services ==="
	$(LEGION_LIMACTL) shell legion sudo systemd-analyze blame | head -10
	@echo ""
	@echo "=== Disk Usage ==="
	$(LEGION_LIMACTL) shell legion df -h /

# Clean up VM and temporary files
clean:
	$(LEGION_LIMACTL) delete -f legion 2>/dev/null || true
	rm -rf /tmp/lima-build

# Clean everything including built artifacts
distclean: clean
	rm -rf $(OUTPUT_DIR)
