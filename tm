#!/usr/bin/env bash
# tm: pick a tmux session from a list and attach to it.
# Sessions marked as daemons (t -d, or d here) are listed under "Daemons".
#
#   enter     attach (or switch, if already inside tmux)
#   j/k       move
#   d         move session in/out of Daemons
#   r         rename session
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
    '#{session_id}'             # 8
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
    printf 'enter attach · / search · q quit\n'
    printf 'd daemon · r rename · s sort · x kill'
}

# Id of the Daemons heading row. It must not be empty: --track never finds
# an empty id after a reload, and fzf then stops taking keys. Session ids
# look like $3, so this cannot match one.
heading=':daemons:'

# Output: <id> TAB <padded name> TAB <details>. The id is the tmux session
# id, which the bindings target. It survives a rename, and it works as a
# target when the name has . or : in it, which a name target does not.
# fzf shows fields 2.. and only searches field 2.
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
                $8, $1, $4, $6, ago($2), ago($3), ($5 > 0 ? "\033[32mattached\033[0m" : ""))
            if ($7) daemons[++nd] = line; else print line
        }
        END {
            print heading "\t\033[33m── Daemons ──\033[0m\t"
            for (i = 1; i <= nd; i++) print daemons[i]
        }'
}

toggle_daemon() {
    [[ -z "$1" || "$1" == "$heading" ]] && return
    if [[ -n "$(tmux show-options -t "$1" -qv @daemon)" ]]; then
        tmux set-option -t "$1" -u @daemon
    else
        tmux set-option -t "$1" @daemon 1
    fi
}

self="$(readlink -f "$0")"
keys='j,k,d,r,s,x,q,/'
# Leaves search or rename mode. The query stays but filters nothing, and the
# reload shows the whole list again, which turning search off does not do.
leave_input="hide-input+disable-search+change-prompt(search> )+rebind($keys)+reload('$self' --list)"

# r on a session: show the input with its current name filled in. Search
# stays off, which keeps the list still while the new name is typed.
start_rename() {
    [[ -z "$1" || "$1" == "$heading" ]] && return
    printf 'show-input+change-prompt(rename> )+unbind(%s)+change-query:%s\n' \
        "$keys" "$(tmux display-message -p -t "$1" '#{session_name}')"
}

# enter in rename mode. . and : become _, as in t. An empty name cancels, and
# a tmux error stays on screen in the prompt with rename mode still open.
finish_rename() {
    local new="${2//[.:]/_}" err
    if [[ -n "$new" && "$1" != "$heading" ]] &&
        ! err="$(tmux rename-session -t "$1" "$new" 2>&1)"; then
        echo "change-prompt:rename ($err)> "
    else
        echo "$leave_input"
    fi
}

case "${1:-}" in
    --list)      list; exit ;;
    --header)    header; exit ;;
    --sort)      cycle_sort; exit ;;
    --toggle)    toggle_daemon "${2:-}"; exit ;;
    --rename)    start_rename "${2:-}"; exit ;;
    --rename-to) finish_rename "${2:-}" "${3:-}"; exit ;;
esac

if ! tmux list-sessions &>/dev/null; then
    echo "no tmux sessions" >&2
    exit 1
fi

# Shell test for the bindings: the focused row is a session, not the heading.
is_session="[ -n {1} ] && [ {1} != '$heading' ]"

# Letters are commands until / opens the search or r opens a rename. The
# input state tells the three modes apart: hidden, enabled for a search, and
# disabled (search off) for a rename. Outside a search, search is off, so an
# old query filters nothing, and / clears it when a new search starts.
# Clearing it on the way out fails: fzf drops clear-query when the same
# transform also runs hide-input. --track with --id-nth=1 keeps the cursor
# on a session when d moves it or r renames it, but it also makes fzf drop
# any action after reload, so reload goes last.
# The bindings are bash, and --with-shell runs them with bash whatever $SHELL
# is.
pick=$(list | fzf \
    --ansi --no-sort --track --id-nth=1 --with-shell='bash -c' \
    --delimiter=$'\t' --with-nth=2.. --nth=1 \
    --no-input --disabled --prompt='search> ' \
    --header="$(header)" --header-first \
    --layout=reverse --border \
    --preview="$is_session && tmux capture-pane -ep -t {1}" \
    --preview-window='right,55%' \
    --bind='j:down,k:up' \
    --bind="d:execute-silent('$self' --toggle {1})+reload('$self' --list)" \
    --bind="s:execute-silent('$self' --sort)+transform-header('$self' --header)+reload('$self' --list)" \
    --bind="x,ctrl-x:execute-silent($is_session && tmux kill-session -t {1})+reload('$self' --list)" \
    --bind="r:transform:'$self' --rename {1}" \
    --bind="/:show-input+clear-query+enable-search+unbind($keys)" \
    --bind='q:abort' \
    --bind="esc:transform:[[ \$FZF_INPUT_STATE == hidden ]] && echo abort || echo \"$leave_input\"" \
    --bind="enter:transform:if [[ \$FZF_INPUT_STATE == disabled ]]; then '$self' --rename-to {1} {q}; else $is_session && echo accept; fi" \
    ) || exit 0

id="${pick%%$'\t'*}"
[[ -z "$id" || "$id" == "$heading" ]] && exit 0

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "$id"
else
    exec tmux attach-session -t "$id"
fi
