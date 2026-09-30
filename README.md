# Tmux Minder

Tmux Minder is two commands for named tmux sessions. `t` opens a session by name, and `tm` is a full-screen list of your sessions that attaches to the one you pick. Sessions for long, non-interactive jobs like a web server or a VPN client can be marked as daemons. `tm` keeps those in their own section at the bottom.

## Requirements

- bash
- tmux (tested with 3.7)
- fzf 0.71 or newer, for `--id-nth`

## Install

The commands are plain bash scripts. Link both into a directory on your `PATH`:

```sh
git clone https://github.com/postfunctional-org/tmux-minder.git
cd tmux-minder
ln -s "$PWD/t" "$PWD/tm" ~/bin/
```

## t

```
t <name>                  open a session, creating it if needed
t -d <name>               the same, and mark it as a daemon
t -d <name> <command...>  start the command in a new daemon session
```

Names may contain spaces, as in `t my project`. `t` replaces `.` and `:` with `_`, because tmux reads them in a target as window and pane separators. Inside tmux, `t` and `tm` switch the current client to the session instead of nesting one tmux inside another.

Given a command, `t -d` types it into the new session's shell and returns without attaching. The shell stays open after the command exits. The output stays on screen, and the command is easy to run again.

```sh
t -d web python3 -m http.server 8000
```

If the session already exists, `t -d` marks it as a daemon and attaches to it. The command is not run.

## tm

Each row is one session. The columns are the window count, the program in the active pane, the idle time, and the uptime. A green `attached` marks a session that a client is using. The preview on the right is the session's current screen.

Letters in `tm` are commands. Search is a separate mode that `/` opens.

| key | action |
|---|---|
| enter | attach, or switch inside tmux |
| j, k, arrows | move |
| d | move the session in or out of Daemons |
| s | cycle the sort: recent, name, created |
| x, ctrl-x | kill the session |
| / | search session names, esc to leave |
| q, esc | quit |

The sort applies within each section. `tm` remembers it in `~/.cache/tmux-minder/sort` (or under `$XDG_CACHE_HOME`).

## Daemons

A daemon is an ordinary tmux session with the user option `@daemon` set. `t -d` and the `d` key set and clear it. It can also be set by hand:

```sh
tmux set-option -t web: @daemon 1
```

Nothing supervises a daemon. When a program started by `t -d` exits, its session stays open at a shell prompt. The program column in `tm` then shows the shell. The option lives on the session and disappears with it, or with the tmux server.

## License

MIT
