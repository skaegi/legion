#!/bin/bash

set -e

# if ~/.claude folder is empty create and copy contents from init and defaults
mkdir -p "$HOME/.claude"
if [ ! -e "$HOME/.claude/.claude.json" ] && [ -f "$HOME/.legion/.init/.claude.json" ]; then
    cp "$HOME/.legion/.init/.claude.json" "$HOME/.claude/.claude.json"
fi
cp -n -r "$HOME/.legion/.defaults/." "$HOME/.claude/"

# Check if this is an initialization run
if ! jq -e 'has("projects")' $HOME/.legion/.init/.claude.json >/dev/null 2>&1; then

    # Files to check/create
    files=(".claude.json" ".claude.json.backup")
    for file in "${files[@]}"; do
        if [ ! -f "$HOME/.claude/$file" ]; then
            echo '{}' > "$HOME/.claude/$file"
        fi

        if [ ! -e "$HOME/$file" ]; then
            ln -s "$HOME/.claude/$file" "$HOME/$file"
        fi
    done

    # Background function to wait for .claude.json/.credentials.json and copy to .init /.credentials
    (
        # Wait for both required files to exist
        while ! jq -e 'has("projects")' ~/.claude.json >/dev/null 2>&1; do
            sleep 1
        done

        # Copy configuration files to .default directory and link
        cp "$HOME/.claude.json" "$HOME/.legion/.init/.claude.json"

        # Copy credentials to .credentials directory and (best effort) link
        cp "$HOME/.claude/.credentials.json" "$HOME/.legion/.credentials/.credentials.json" || true
        rm "$HOME/.claude/.credentials.json" || true
        ln -s "$HOME/.legion/.credentials/.credentials.json" "$HOME/.claude/.credentials.json" || true
    ) &
else
    # Link .credential.json if not present
    if [ ! -e "$HOME/.claude/.credentials.json" ] && [ -f "$HOME/.legion/.credentials/.credentials.json" ]; then
        ln -s "$HOME/.legion/.credentials/.credentials.json" "$HOME/.claude/.credentials.json"
    fi

    # Link .claude.json if not present
    if [ ! -e "$HOME/.claude.json" ]; then
        ln -s "$HOME/.claude/.claude.json" "$HOME/.claude.json"
    fi
fi

