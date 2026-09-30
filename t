#!/usr/bin/env bash
# t <name>                  open a named tmux session, creating it if needed
# t -d <name> [command...]  same, but list it under Daemons in tm. With a
#                           command, it is typed into the session's shell and
#                           left running in the background (no attach).
# Inside tmux it switches the current client instead of nesting.
set -euo pipefail

usage() { echo "usage: t [-d] <name> [command...]" >&2; exit 1; }

daemon=0
if [[ "${1:-}" == -d ]]; then
    daemon=1
    shift
fi
[[ $# -eq 0 ]] && usage

if (( daemon )); then
    name="$1"; shift
    cmd="$*"
else
    name="$*"
    cmd=""
fi
# A target reads . and : as window and pane separators, so a session name
# with either in it cannot be targeted
name="${name//[.:]/_}"

if tmux has-session -t "=$name" 2>/dev/null; then
    [[ -n "$cmd" ]] && echo "t: session '$name' already exists, command not run" >&2
    cmd=""
else
    tmux new-session -d -s "$name"
fi

# Option commands need the trailing colon in =name: here. A bare =name is
# rejected with "no such session".
if (( daemon )); then
    tmux set-option -t "=$name:" @daemon 1
fi

if [[ -n "$cmd" ]]; then
    tmux send-keys -t "=$name:" -l "$cmd"
    tmux send-keys -t "=$name:" Enter
    echo "started daemon '$name': $cmd"
    exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "=$name"
else
    exec tmux attach-session -t "=$name"
fi
