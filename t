#!/usr/bin/env bash
# t <name>: open a named tmux session, creating it if it does not exist.
# Inside tmux it switches the current client instead of nesting.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "usage: t <name>" >&2
    exit 1
fi

name="$*"
# tmux does not allow . or : in session names
name="${name//[.:]/_}"

if ! tmux has-session -t "=$name" 2>/dev/null; then
    tmux new-session -d -s "$name"
fi

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "=$name"
else
    exec tmux attach-session -t "=$name"
fi
