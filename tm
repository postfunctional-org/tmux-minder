#!/usr/bin/env bash
# tm: pick a tmux session from a list and attach to it.
# Sessions marked as daemons (t -d, or d here) are listed under "Daemons".
#
#   enter     attach (or switch, if already inside tmux)
#   j/k       move
#   d         move session in/out of Daemons
#   s         cycle sort: recent, name, created
#   x         kill session
#   /         search (esc leaves search)
#   q, esc    quit
set -euo pipefail

sortfile="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-minder/sort"
sorts=(recent name created)

# One tab-separated row per session. awk and sort refer to these by number.
fields=(
    '#{session_name}'           # 1
    '#{session_activity}'       # 2
    '#{session_created}'        # 3
    '#{session_windows}'        # 4
    '#{session_attached}'       # 5
    '#{pane_current_command}'   # 6
    '#{?@daemon,1,0}'           # 7
)

get_sort() {
    local s
    s="$(cat "$sortfile" 2>/dev/null || true)"
    [[ " ${sorts[*]} " == *" $s "* ]] && echo "$s" || echo recent
}

cycle_sort() {
    local cur i
    cur="$(get_sort)"
    for i in "${!sorts[@]}"; do
        [[ "${sorts[i]}" == "$cur" ]] && break
    done
    mkdir -p "$(dirname "$sortfile")"
    echo "${sorts[(i + 1) % ${#sorts[@]}]}" > "$sortfile"
}

header() {
    printf 'sort: %s\n' "$(get_sort)"
    printf 'enter attach · d daemon · s sort · x kill · / search · q quit'
}

# Id of the Daemons heading row. It must not be empty: --track never finds
# an empty id after a reload, and fzf then stops taking keys. tmux does not
# allow ':' in session names, so this id cannot match a real session.
heading=':daemons:'

# Output: <id> TAB <padded name> TAB <details>. The id is the session name
# the bindings target. fzf shows fields 2.. and only searches field 2.
list() {
    local key
    case "$(get_sort)" in
        name)    key='-k1,1f' ;;
        created) key='-k3,3nr' ;;
        *)       key='-k2,2nr' ;;
    esac
    tmux list-sessions -F "$(IFS=$'\t'; echo "${fields[*]}")" 2>/dev/null |
    sort -t$'\t' $key |
    awk -F'\t' -v now="$(date +%s)" -v heading="$heading" '
        function ago(t,  d) {
            d = now - t
            if (d < 60)    return d "s"
            if (d < 3600)  return int(d / 60) "m"
            if (d < 86400) return int(d / 3600) "h"
            return int(d / 86400) "d"
        }
        {
            line = sprintf("%s\t%-24.24s\t%2dw  %-12.12s idle %-4s up %-4s %s",
                $1, $1, $4, $6, ago($2), ago($3), ($5 > 0 ? "\033[32mattached\033[0m" : ""))
            if ($7) daemons[++nd] = line; else print line
        }
        END {
            print heading "\t\033[33m── Daemons ──\033[0m\t"
            for (i = 1; i <= nd; i++) print daemons[i]
        }'
}

# Option commands need the trailing colon in =name: here. A bare =name is
# rejected with "no such session".
toggle_daemon() {
    [[ -z "$1" || "$1" == "$heading" ]] && return
    if [[ -n "$(tmux show-options -t "=$1:" -qv @daemon)" ]]; then
        tmux set-option -t "=$1:" -u @daemon
    else
        tmux set-option -t "=$1:" @daemon 1
    fi
}

case "${1:-}" in
    --list)   list; exit ;;
    --header) header; exit ;;
    --sort)   cycle_sort; exit ;;
    --toggle) toggle_daemon "${2:-}"; exit ;;
esac

if ! tmux list-sessions &>/dev/null; then
    echo "no tmux sessions" >&2
    exit 1
fi

self="$(readlink -f "$0")"
# Shell test for the bindings: the focused row is a session, not the heading.
is_session="[ -n {1} ] && [ {1} != '$heading' ]"
keys='j,k,d,s,x,q,/'

# Letters are commands until / opens the search. Inside transform,
# clear-query alone leaves the list filtered, hence search(). --track with
# --id-nth=1 keeps the cursor on a session when d moves it to another section,
# but it also makes fzf drop any action after reload, so reload goes last.
pick=$(list | fzf \
    --ansi --no-sort --track --id-nth=1 \
    --delimiter=$'\t' --with-nth=2.. --nth=1 \
    --no-input --prompt='search> ' \
    --header="$(header)" --header-first \
    --layout=reverse --height=80% --border \
    --preview="$is_session && tmux capture-pane -ep -t ={1}:" \
    --preview-window='right,55%' \
    --bind='j:down,k:up' \
    --bind="d:execute-silent('$self' --toggle {1})+reload('$self' --list)" \
    --bind="s:execute-silent('$self' --sort)+transform-header('$self' --header)+reload('$self' --list)" \
    --bind="x,ctrl-x:execute-silent($is_session && tmux kill-session -t ={1})+reload('$self' --list)" \
    --bind="/:show-input+unbind($keys)" \
    --bind='q:abort' \
    --bind="esc:transform:[[ \$FZF_INPUT_STATE == hidden ]] && echo abort || echo 'clear-query+search()+hide-input+rebind($keys)'" \
    --bind="enter:transform:$is_session && echo accept" \
    ) || exit 0

name="${pick%%$'\t'*}"
[[ -z "$name" || "$name" == "$heading" ]] && exit 0

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "=$name"
else
    exec tmux attach-session -t "=$name"
fi
