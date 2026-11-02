# dirhist

Per-directory command history for bash. Record only the directories you choose. Each command is appended as it runs, not when the shell exits. Global bash history is left unchanged.

## Install

`dirhist` has to be sourced. Add this to `~/.bashrc`:

```bash
source /path/to/dirhist.bash
```

Open a new shell, then start recording the current directory:

```bash
dirhist on
```

`dirhist start` does the same. With no arguments, `dirhist` prints this directory's history.

## Commands

```
dirhist                            show this directory's history
dirhist history [-u] [-n N] [dir|N] show this directory's history, or dir's
                                   -n N shows the newest N commands
                                   -u prints each command once, with no number or date
dirhist on|start [dir|N]           record this directory, or directory N
dirhist off|stop [dir|N]           stop recording this directory, or directory N, and keep its commands
dirhist rm|remove [dir|N]          remove dir from the list and delete its commands
dirhist ls|list                    list numbered directories, marked on or off
dirhist status                     show on or off, the history file, and the config
dirhist grep [-a] [-u] [-v PAT] [PAT] search this directory's history
                                   -a searches every directory.
                                   -u prints each matching command once, with no number or date
                                   -v PAT without another PAT only excludes PAT
                                   PAT keeps commands that contain it.
                                   The flags and PAT can be in either order
dirhist themes [name]              show a sample of each color theme
dirhist init                       create the config file if it is missing
dirhist ignore                     show ignore rules for this directory
dirhist ignore PAT                 ignore PAT in this directory
dirhist ignore -d PAT              stop ignoring PAT in this directory
dirhist ignore -g PAT              ignore PAT in every recorded directory
dirhist ignore -g -d PAT           stop ignoring PAT everywhere
dirhist prune                      drop recorded directories that are gone
dirhist clean [-n N] [dir|N]       delete this directory's commands, or dir's
                                   -n N keeps the newest N commands
dirhist alias [NAME]               print or set the command alias
dirhist alias -d                   remove the alias
dirhist version|-V|--version       print version
```

Tab completion fills commands, theme names, and recorded directories.

`alias = dh` under `[global]` makes `dh` run `dirhist`. `dirhist` defines that alias when the file is sourced. It does not belong in `~/.bashrc`. `dirhist alias dh` writes the same line.

`on` means the directory is still recorded. `off` means recording has stopped and its commands are still kept. `remove` deletes those commands.

`dirhist list` prints a number in front of each directory. That number stands in for the path: `dirhist history 1`, `dirhist on 1`, `dirhist off 1`, `dirhist clean 1`, and `dirhist rm 1` use it. With no number, `on`, `off`, and `clean` use the current directory. `dirhist history -n 5 1` shows the newest 5 commands from directory 1. `dirhist history -u` prints each command once and keeps the latest copy. The number and the date prefix are left off. `dirhist -u` does the same. `dirhist history -u -n 5` shows the newest 5 of those.

`dirhist clean` deletes the current directory's commands. `dirhist clean ~/src/project` deletes that directory's commands. `dirhist clean -n 50` keeps the newest 50 there. Other directories stay.

`dirhist grep -v PAT` without another PAT only excludes commands that contain PAT. `dirhist grep help -v dirhist` and `dirhist grep -v dirhist help` both keep commands that contain `help` and drop commands that contain `dirhist`. `-v` can be repeated. `-a` searches every recorded directory. `-u` prints each matching command once, with no number or date, and keeps the latest. It combines with `-a` and `-v` in either order.

## Files

| Path | Purpose |
| --- | --- |
| `~/.dirhist` | Directories currently recording, one physical path per line |
| `~/.dirhist_history` | Commands for every directory |
| `~/.dirhist.lock` | Empty lock so two shells cannot write the history at once |
| `~/.config/dirhist/config` | Options and ignore rules |

History entries look like this:

```
@@ /physical/path
[2026-11-01]=[12:00:00]──► echo hello
```

Paths are physical (`pwd -P`). `cd` is stored for the directory you leave, and also for the directory you enter when that one is recorded. A command the shell itself drops because of a leading space is not recorded. Names listed in `HISTIGNORE`, including aliases such as `ls`, still are.

## Config

`dirhist init` creates `~/.config/dirhist/config` when it is missing.

```ini
[options]
date = on
color = on
status_color = on
theme = crimson
max_lines = 500

[global]
# alias = dh
echo *

[/home/you/project]
pwd
max_lines = 50
```

`date`, `color`, and `status_color` accept `on` or `off` and default to `on`.

- `date` writes the `[YYYY-MM-DD]=[HH:MM:SS]──►` prefix.
- `color` colors history. The whole command uses the selected theme.
- `status_color` colors the `on`, `off`, `history`, and `config` labels. Paths stay plain. `on` is green, `off` is red, and the other labels are solarized dark.
- `theme` is `crimson`, `ocean`, `forest`, `amber`, or `violet`. The default is `crimson`. The old names `history` and `ember` still select `crimson`.
- `max_lines` is how many commands to keep per directory. Unset means no limit. A `max_lines` line in a directory section overwrites `[options]` for that directory. `off` or `0` there means no limit.
- `alias` under `[global]` is a command name `dirhist` defines, for example `alias = dh`. It is not an ignore pattern. `dirhist alias dh` writes that line.

Help usage lines use solarized dark, like `bat`. Descriptions stay the terminal color. Set `NO_COLOR` to leave help plain.

A pattern ignores that command and anything after it. `ls` ignores `ls`, `ls -alh`, and `ls /tmp`. It does not ignore `lsblk`. `*` still matches any text. Patterns under `[global]` apply everywhere. A `[/absolute/path]` or `[dir /absolute/path]` section applies only there. Use the physical path.
