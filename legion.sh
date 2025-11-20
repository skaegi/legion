#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
LEGION_LIMACTL="$SCRIPT_DIR/_output/bin/legion-limactl"
VM_HOME="$HOME.linux"

# Parse debug flag
DEBUG=false
if [ "$1" = "--debug" ]; then
    DEBUG=true
    shift
fi

debug_echo() {
    if [ "$DEBUG" = true ]; then
        echo "$@"
    fi
}

setup_credentials() {
    LEGION_CREDS="$HOME/.legion/.credentials"
    if CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) && [ -n "$CREDS" ]; then
        echo "$CREDS" > "$LEGION_CREDS/.credentials.json"
    fi
    if [ -f "$HOME/.claude.json" ] && command -v jq >/dev/null 2>&1; then
        if OAUTH=$(jq -r '.oauthAccount // empty' "$HOME/.claude.json" 2>/dev/null) && [ -n "$OAUTH" ]; then
            echo "$OAUTH" > "$LEGION_CREDS/.oauthAccount.json"
        fi
    fi
}

cleanup_vm() {
    if [ "$VM_STARTED" = true ]; then
        debug_echo "Deleting VM $vm_name..."
        (
            "$LEGION_LIMACTL" delete --force --log-level error "$vm_name"
            debug_echo "Legion VM cleaned up."
        )&
    fi
}

# Check if legion-limactl exists
if [ ! -f "$LEGION_LIMACTL" ]; then
    echo "Error: legion-limactl not found at $LEGION_LIMACTL"
    echo "Run 'make build-limactl' to build it first."
    exit 1
fi

# Get current directory and translate to project name
project_name="$(basename "$(pwd)")_$(echo -n "$(pwd)" | shasum -a 256 | cut -c1-8)"
vm_name="legion-$project_name"

# Check if first argument is "shell" for VM shell mode
if [ "$1" = "shell" ]; then
    shift  # Remove "shell" from arguments

    # Check if VM is running
    if ! "$LEGION_LIMACTL" list | grep -q "^$vm_name.*Running"; then
        echo "Error: legion VM for this project is not running."
        echo "Start it first by running 'legion.sh' in this directory."
        exit 1
    fi

    # Execute command in the running VM
    "$LEGION_LIMACTL" shell --workdir /workspace "$vm_name" "$@"
    exit $?
fi

# Create legion directories if they don't exist
mkdir -p ~/.legion/.init
mkdir -p ~/.legion/.defaults
mkdir -p ~/.legion/.credentials
mkdir -p ~/.legion/"$project_name"

# Check if legion network exists, create if not
if ! "$LEGION_LIMACTL" network list | grep -q "^legion"; then
    debug_echo "Creating legion network..."
    "$LEGION_LIMACTL" network create legion --policy "$SCRIPT_DIR/policy.yaml" --gateway 192.168.123.1/24
fi

# Track whether we started the VM (for cleanup)
VM_STARTED=false
trap cleanup_vm EXIT

# Check if VM is already running
if "$LEGION_LIMACTL" list | grep -q "^$vm_name.*Running"; then
    debug_echo "VM $vm_name is already running."
elif "$LEGION_LIMACTL" list | grep -q "^$vm_name"; then
    debug_echo "VM $vm_name exists but is not running. Starting it..."
    setup_credentials
    TIMEFORMAT='%3R'
    duration=$( { time "$LEGION_LIMACTL" start -y --log-level error "$vm_name" ; } 2>&1 )
    debug_echo "VM started in ${duration}s"
    VM_STARTED=true
else
    debug_echo "Creating and starting VM $vm_name..."
    setup_credentials
    TIMEFORMAT='%3R'
    duration=$( { time "$LEGION_LIMACTL" start -y --log-level error --network lima:legion --name="$vm_name" \
        --set ".images[0].location=\"$SCRIPT_DIR/_output/legion-rootfs.img\"" \
        --set ".images[0].kernel.location=\"$SCRIPT_DIR/_output/legion-vmlinux\"" \
        --set ".mounts += [{\"location\": \"$(pwd)\", \"mountPoint\": \"/workspace\", \"writable\": true}]" \
        "$SCRIPT_DIR/legion.yaml" ; } 2>&1 )
    debug_echo "VM created and started in ${duration}s"
    VM_STARTED=true
fi

# If no additional arguments, open a shell
if [ $# -eq 0 ]; then
    debug_echo "Opening shell in VM $vm_name..."
    "$LEGION_LIMACTL" shell --workdir /workspace "$vm_name"
else
    # Run the provided command
    debug_echo "Running command in VM $vm_name: $*"
    "$LEGION_LIMACTL" shell --workdir /workspace "$vm_name" "$@"
fi

# Turn off bracket paste after shell exits
printf '\e[?2004l'
