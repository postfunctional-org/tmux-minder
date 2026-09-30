#!/usr/bin/env bash
# tm: pick a tmux session from a list and attach to it.
#
#   enter     attach (or switch, if already inside tmux)
#   ctrl-x    kill session
#   esc       quit
set -euo pipefail

# One tab-separated row per session. awk and sort refer to these by number.
fields=(
    '#{session_name}'           # 1
    '#{session_activity}'       # 2
    '#{session_created}'        # 3
    '#{session_windows}'        # 4
    '#{session_attached}'       # 5
    '#{pane_current_command}'   # 6
)

# Output: <raw name> TAB <padded name> TAB <details>. The raw name is what
# the bindings target. fzf shows fields 2.. and only searches field 2.
list() {
    tmux list-sessions -F "$(IFS=$'\t'; echo "${fields[*]}")" 2>/dev/null |
    sort -t$'\t' -k2,2nr |
    awk -F'\t' -v now="$(date +%s)" '
        function ago(t,  d) {
            d = now - t
            if (d < 60)    return d "s"
            if (d < 3600)  return int(d / 60) "m"
            if (d < 86400) return int(d / 3600) "h"
            return int(d / 86400) "d"
        }
        {
            printf "%s\t%-24.24s\t%2dw  %-12.12s idle %-4s up %-4s %s\n",
                $1, $1, $4, $6, ago($2), ago($3), ($5 > 0 ? "\033[32mattached\033[0m" : "")
        }'
}

case "${1:-}" in
    --list)   list; exit ;;
esac

if ! tmux list-sessions &>/dev/null; then
    echo "no tmux sessions" >&2
    exit 1
fi

self="$(readlink -f "$0")"

pick=$(list | fzf \
    --ansi --no-sort \
    --delimiter=$'\t' --with-nth=2.. --nth=1 \
    --prompt='search> ' \
    --header='enter attach · ctrl-x kill · esc quit' --header-first \
    --layout=reverse --height=80% --border \
    --preview='tmux capture-pane -ep -t ={1}:' \
    --preview-window='right,55%' \
    --bind="ctrl-x:execute-silent(tmux kill-session -t ={1})+reload('$self' --list)" \
    ) || exit 0

name="${pick%%$'\t'*}"
[[ -z "$name" ]] && exit 0

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "=$name"
else
    exec tmux attach-session -t "=$name"
fi
