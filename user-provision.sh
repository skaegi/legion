#!/bin/bash

set -e

# if ~/.claude folder is empty create and copy contents from init and defaults
mkdir -p "$HOME/.claude"
if [ ! -e "$HOME/.claude/.claude.json" ] && [ -f "$HOME/.legion/.init/.claude/.claude.json" ]; then
    cp "$HOME/.legion/.init/.claude/.claude.json" "$HOME/.claude/.claude.json"
fi
cp -n -r "$HOME/.legion/.config/.claude/." "$HOME/.claude/"

# Check if this is an initialization run
if [ ! -f "$HOME/.legion/.init/.claude/.claude.json" ]; then

    # Create .claude.json
    if [ ! -f "$HOME/.claude/.claude.json" ]; then
        echo '{}' > "$HOME/.claude/$file"
    fi

    if [ ! -e "$HOME/.claude.json" ]; then
        ln -s "$HOME/.claude/.claude.json" "$HOME/$.claude.json"
    fi

    # Background function to wait for .claude.json and .credentials.json and copy to .init and .claude
    (
        # Wait for both required files to exist
        while ! jq -e 'has("projects")' ~/.claude.json >/dev/null 2>&1; do
            sleep 1
        done

        # Copy configuration files to .default directory and link
        cp "$HOME/.claude.json" "$HOME/.legion/.init/.claude/.claude.json"

        # Copy credentials to .config/.claude directory and (best effort) link
        cp "$HOME/.claude/.credentials.json" "$HOME/.legion/.credentials/.claude/.credentials.json" || true
        rm "$HOME/.claude/.credentials.json" || true
        ln -s "$HOME/.legion/.credentials/.claude/.credentials.json" "$HOME/.claude/.credentials.json" || true
    ) &
else
    # Link .credential.json if not present
    if [ ! -e "$HOME/.claude/.credentials.json" ] && [ -f "$HOME/.legion/.credentials/.claude/.credentials.json" ]; then
        ln -s "$HOME/.legion/.credentials/.claude/.credentials.json" "$HOME/.claude/.credentials.json"
    fi

    # Link .claude.json if not present
    if [ ! -e "$HOME/.claude.json" ]; then
        ln -s "$HOME/.claude/.claude.json" "$HOME/.claude.json"
    fi
fi

# Merge oauthAccount if available
if [ -f "$HOME/.legion/.credentials/.claude/.oauthAccount.json" ] && command -v jq >/dev/null 2>&1; then
    OAUTH=$(cat "$HOME/.legion/.credentials/.claude/.oauthAccount.json")
    jq --argjson oauth "$OAUTH" '.oauthAccount = $oauth' "$HOME/.claude/.claude.json" > "$HOME/.claude/.claude.json.tmp"
    mv "$HOME/.claude/.claude.json.tmp" "$HOME/.claude/.claude.json"
fi

