# Dockerfile to build custom Kata Containers kernel
# Based on Kata kernel 6.12.52 with additional features for Lima

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    bc \
    bison \
    flex \
    libelf-dev \
    libssl-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Download Kata kernel source
WORKDIR /build
RUN curl -L https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.52.tar.xz | tar -xJ
WORKDIR /build/linux-6.12.52

# Copy kernel config and custom additions
COPY .config .config
COPY extras.conf /tmp/extras.conf
RUN cat /tmp/extras.conf >> .config

# Build the kernel
RUN make olddefconfig
RUN make -j$(nproc)

# Extract the uncompressed kernel
FROM scratch
COPY --from=builder /build/linux-6.12.52/arch/arm64/boot/Image /legion-vmlinux
