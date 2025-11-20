#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
LEGION_LIMACTL="$SCRIPT_DIR/_output/bin/legion-limactl"

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

setup_config() {
    LEGION_CONFIG="$HOME/.legion/.config"
    #claude
    mkdir -p "$LEGION_CONFIG/.claude"
    if [ -f "$HOME/.claude/settings.json" ]; then
        if [ ! -f "$LEGION_CONFIG/.claude/settings.json" ] || ! cmp -s "$HOME/.claude/settings.json" "$LEGION_CONFIG/.claude/settings.json"; then
            cp "$HOME/.claude/settings.json" "$LEGION_CONFIG/.claude/settings.json"
        fi
    fi

    if [ -f "$HOME/.claude/statusline.sh" ]; then
        if [ ! -f "$LEGION_CONFIG/.claude/statusline.sh" ] || ! cmp -s "$HOME/.claude/statusline.sh" "$LEGION_CONFIG/.claude/statusline.sh"; then
            cp "$HOME/.claude/statusline.sh" "$LEGION_CONFIG/.claude/statusline.sh"
        fi
    fi
}

setup_credentials() {
    LEGION_CREDENTIALS="$HOME/.legion/.credentials"
    #claude
    mkdir -p "$LEGION_CREDENTIALS/.claude"
    if CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) && [ -n "$CREDS" ]; then
        echo "$CREDS" > "$LEGION_CREDENTIALS/.claude/.credentials.json"
    fi

    if [ -f "$HOME/.claude.json" ] && command -v jq >/dev/null 2>&1; then
        if OAUTH=$(jq -r '.oauthAccount // empty' "$HOME/.claude.json" 2>/dev/null) && [ -n "$OAUTH" ]; then
            echo "$OAUTH" > "$LEGION_CREDENTIALS/.claude/.oauthAccount.json"
        fi
    fi
}

setup_init() {
    LEGION_INIT="$HOME/.legion/.init"
    #claude
    mkdir -p "$LEGION_INIT/.claude"
    if [ ! -f "$LEGION_INIT/.claude/.claude.json" ] && [ -f "$HOME/.claude.json" ]; then
        # Default init configuration
        DEFAULT_CLAUDE_JSON='{
            "numStartups": 1,
            "installMethod": "global",
            "autoUpdates": true,
            "hasCompletedOnboarding": true,
            "projects": {
                "/workspace": {
                    "allowedTools": [],
                    "mcpContextUris": [],
                    "mcpServers": {},
                    "enabledMcpjsonServers": [],
                    "disabledMcpjsonServers": [],
                    "hasTrustDialogAccepted": true,
                    "projectOnboardingSeenCount": 1,
                    "hasClaudeMdExternalIncludesApproved": false,
                    "hasClaudeMdExternalIncludesWarningShown": false,
                    "exampleFiles": []
                }
            }
        }'

        # Extract and merge values from existing Claude config if available, otherwise use defaults
        if command -v jq >/dev/null 2>&1; then
            CLAUDE_VALUES=$(jq '{theme: .theme}' "$HOME/.claude.json" 2>/dev/null)
            jq -n --argjson defaults "$DEFAULT_CLAUDE_JSON" --argjson claude "$CLAUDE_VALUES" '$defaults * $claude' > "$LEGION_INIT/.claude/.claude.json"
        else
            echo "$DEFAULT_CLAUDE_JSON" > "$LEGION_INIT/.claude/.claude.json"
        fi
    fi
}

setup_mounts() {
    setup_config
    setup_credentials
    setup_init
    mkdir -p ~/.legion/"$project_name"
}

cleanup_vm() {
    # Turn off bracket paste after shell exits
    printf '\e[?2004l'
    
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
    setup_mounts
    TIMEFORMAT='%3R'
    duration=$( { time "$LEGION_LIMACTL" start -y --log-level error "$vm_name" ; } 2>&1 )
    debug_echo "VM started in ${duration}s"
    VM_STARTED=true
else
    debug_echo "Creating and starting VM $vm_name..."
    setup_mounts
    TIMEFORMAT='%3R'
    duration=$( { time "$LEGION_LIMACTL" start -y --log-level error --network lima:legion --name="$vm_name" \
        --set ".images[0].location=\"$SCRIPT_DIR/_output/legion-rootfs.img\"" \
        --set ".images[0].kernel.location=\"$SCRIPT_DIR/_output/legion-vmlinux\"" \
        --set ".mounts += [{\"location\": \"$(pwd)\", \"mountPoint\": \"/workspace\", \"writable\": true}]" \
        --set ".mounts += [{\"location\": \"~/.legion/$project_name\", \"mountPoint\": \"{{.Home}}/.claude\", \"writable\": true}]" \
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
