#!/usr/bin/env bash
# Per-directory command history.
#
# Source this file from ~/.bashrc. Then, in a directory you want recorded:
#   dirhist on
#   dirhist start
# That path is appended to ~/.dirhist. Every command run while a
# recorded directory is current is appended to ~/.dirhist_history
# immediately (before the command runs), not when the shell exits. The
# directory is stored with the command. cd is recorded too. Entering another
# recorded directory records that command for the new directory as well.
# dirhist with no arguments shows this directory's history.
#
# A command the shell itself drops for starting with a space is skipped here too.
# cd, ls, and other HISTIGNORE names are still recorded, including when they are aliases.
# Extra ignore rules are read from ~/.config/dirhist/config.
# [options] date, color, and status_color are on or off. All default to on.
# color colors history. status_color colors the on, off, history, and config labels.
# theme is crimson, ocean, forest, amber, or violet. Default is crimson.
# dirhist themes prints a sample of each theme.
# Tab completion covers commands, theme names, and recorded directories.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'dirhist: source this file from ~/.bashrc\n  source %q\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

DIRHIST_VERSION=v1.0.1
DIRHIST_REGISTRY="${DIRHIST_REGISTRY:-$HOME/.dirhist}"
DIRHIST_HISTORY="${DIRHIST_HISTORY:-$HOME/.dirhist_history}"
DIRHIST_LOCK="${DIRHIST_LOCK:-$HOME/.dirhist.lock}"
DIRHIST_CONFIG="${DIRHIST_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/dirhist/config}"

# Solarized dark foreground (base0, #839496), the 256-color value solarized uses.
_DIRHIST_SOL_BASE0=$'\033[38;5;244m'

_dirhist_here() {
  builtin pwd -P 2>/dev/null || builtin printf '%s\n' "$PWD"
}

_dirhist_registered() {
  local dir="$1" line
  [[ -f "$DIRHIST_REGISTRY" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$dir" ]] && return 0
  done < "$DIRHIST_REGISTRY"
  return 1
}

# Print the last assignment of $2 in sections whose header is $1.
# $1 is a physical directory. Prints nothing when the key is absent.
_dirhist_config_scope_value() {
  local want="$1" name="$2" line trimmed header scope="" key found=""
  [[ -n "$want" && -f "${DIRHIST_CONFIG:-}" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if header=$(_dirhist_config_header "$trimmed"); then
      scope=$header
      continue
    fi
    [[ "$scope" == "$want" ]] || continue
    if [[ "$trimmed" =~ ^([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(=|[[:space:]])[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1],,}"
      [[ "$key" == "$name" ]] || continue
      found=$(_dirhist_trim "${BASH_REMATCH[3]}")
      if [[ "$found" == \"*\" || "$found" == \'*\' ]]; then
        found="${found:1:${#found}-2}"
      fi
      found="${found,,}"
    fi
  done < "$DIRHIST_CONFIG"
  builtin printf '%s\n' "$found"
}

# Positive max_lines for one directory, or return 1 when it is not trimmed.
# A max_lines line in that directory's section overwrites [options].
_dirhist_max_lines() {
  local dir="${1:-}" val=""
  if [[ -n "$dir" ]]; then
    val=$(_dirhist_config_scope_value "$dir" max_lines)
  fi
  if [[ -z "$val" ]]; then
    val=$(_dirhist_config_value max_lines)
  fi
  val="${val//[[:space:]]/}"
  case "$val" in
    ""|off|no|false|0) return 1 ;;
  esac
  [[ "$val" =~ ^[0-9]+$ ]] || return 1
  builtin printf '%s\n' "$val"
}

_dirhist_ensure_home() {
  if [[ ! -e "$DIRHIST_HISTORY" ]]; then
    (umask 077; : >> "$DIRHIST_HISTORY") || return 1
  fi
  if [[ ! -e "$DIRHIST_REGISTRY" ]]; then
    (umask 077; : >> "$DIRHIST_REGISTRY") || return 1
  fi
  if [[ -d "$DIRHIST_REGISTRY" ]]; then
    builtin printf 'dirhist: %s is a directory\n' "$DIRHIST_REGISTRY" >&2
    return 1
  fi
  if [[ ! -e "$DIRHIST_LOCK" ]]; then
    (umask 077; : >> "$DIRHIST_LOCK") || return 1
  fi
}

_dirhist_write_entry() {
  local file="$1" dir="$2" date="$3" time="$4" cmd="$5"
  builtin printf '@@ %s\n' "$dir" >> "$file"
  if [[ -n "$date" ]]; then
    builtin printf '[%s]=[%s]──► %s\n' "$date" "$time" "$cmd" >> "$file"
  else
    builtin printf '%s\n' "$cmd" >> "$file"
  fi
}

_dirhist_collect_entry() {
  _dirhist_e_dir+=("$1")
  _dirhist_e_date+=("$2")
  _dirhist_e_time+=("$3")
  _dirhist_e_cmd+=("$4")
}

# Call _dirhist_collect_entry for every stored command.
_dirhist_foreach() {
  local file="$1" line dir="" date="" time="" cmd="" open=0
  local re_mark='^@@ (.*)$'
  local re_stamp='^\[([0-9]{4}-[0-9]{2}-[0-9]{2})\]=\[([0-9]{2}:[0-9]{2}:[0-9]{2})\]──► (.*)$'
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $re_mark ]]; then
      if [[ "$open" == 1 ]]; then
        _dirhist_collect_entry "$dir" "$date" "$time" "$cmd"
      fi
      dir="${BASH_REMATCH[1]}"
      date=""
      time=""
      cmd=""
      open=1
      continue
    fi
    [[ "$open" == 1 ]] || continue
    if [[ -z "$cmd" && -z "$date" && "$line" =~ $re_stamp ]]; then
      date="${BASH_REMATCH[1]}"
      time="${BASH_REMATCH[2]}"
      cmd="${BASH_REMATCH[3]}"
    elif [[ -z "$cmd" && -z "$date" ]]; then
      cmd="$line"
    else
      cmd+=$'\n'"$line"
    fi
  done < "$file"
  if [[ "$open" == 1 ]]; then
    _dirhist_collect_entry "$dir" "$date" "$time" "$cmd"
  fi
}

_dirhist_load_entries() {
  _dirhist_e_dir=()
  _dirhist_e_date=()
  _dirhist_e_time=()
  _dirhist_e_cmd=()
  _dirhist_foreach "$DIRHIST_HISTORY"
}

_dirhist_print_entry() {
  local n="$1" date="$2" time="$3" cmd="$4" use_color="$5" theme="$6"
  local first rest
  first="${cmd%%$'\n'*}"
  if [[ "$cmd" == *$'\n'* ]]; then
    rest="${cmd#*$'\n'}"
  else
    rest=""
  fi
  if [[ -n "$date" ]]; then
    _dirhist_theme_paint "$theme" "$n" "$date" "$time" "$first" "$use_color"
  else
    builtin printf '%5d  %s\n' "$n" "$first"
  fi
  if [[ -n "$rest" ]]; then
    builtin printf '%s\n' "$rest"
  fi
}

# $1 directory filter, empty for every directory
# $2 newest N, empty for all
# $3 include substring, empty to keep every command
# $4 1 to print a directory header when it changes
# $5 name of an array of substrings to skip. Omit it to skip nothing.
# Return 1 when nothing is selected.
_dirhist_render() {
  local filter="$1" limit="$2" pattern="$3" headers="$4"
  local i d theme use_color=0 pos total start k last="" cmd ex skip
  local -a pick=() pick_n=() _dh_no_ex=()
  local -A tally=()
  local -n _dh_excludes="${5:-_dh_no_ex}"
  _dirhist_load_entries
  for i in "${!_dirhist_e_dir[@]}"; do
    d="${_dirhist_e_dir[i]}"
    if [[ -n "$filter" && "$d" != "$filter" ]]; then
      continue
    fi
    tally["$d"]=$(( ${tally["$d"]:-0} + 1 ))
    cmd="${_dirhist_e_cmd[i]}"
    if [[ -n "$pattern" && "$cmd" != *"$pattern"* ]]; then
      continue
    fi
    skip=0
    for ex in "${_dh_excludes[@]}"; do
      if [[ "$cmd" == *"$ex"* ]]; then
        skip=1
        break
      fi
    done
    [[ "$skip" == 1 ]] && continue
    pick+=("$i")
    pick_n+=("${tally["$d"]}")
  done
  total=${#pick[@]}
  (( total > 0 )) || return 1
  start=0
  if [[ -n "$limit" ]] && (( limit < total )); then
    start=$((total - limit))
  fi
  theme=$(_dirhist_theme_name)
  if [[ -t 1 ]] && _dirhist_option_on color; then
    use_color=1
  fi
  for (( pos=start; pos<total; pos++ )); do
    k="${pick[pos]}"
    if [[ "$headers" == 1 && "${_dirhist_e_dir[k]}" != "$last" ]]; then
      builtin printf '%s\n' "${_dirhist_e_dir[k]}"
      last="${_dirhist_e_dir[k]}"
    fi
    _dirhist_print_entry "${pick_n[pos]}" \
      "${_dirhist_e_date[k]}" "${_dirhist_e_time[k]}" "${_dirhist_e_cmd[k]}" \
      "$use_color" "$theme"
  done
}

# Drop the oldest commands in one directory until max_lines remain.
_dirhist_trim_unlocked() {
  local dir="$1" max i d seen=0 drop tmp
  max=$(_dirhist_max_lines "$dir") || return 0
  _dirhist_load_entries
  seen=0
  for i in "${!_dirhist_e_dir[@]}"; do
    [[ "${_dirhist_e_dir[i]}" == "$dir" ]] && seen=$((seen + 1))
  done
  (( seen > max )) || return 0
  drop=$((seen - max))
  seen=0
  tmp=$(mktemp "$(dirname -- "$DIRHIST_HISTORY")/.dirhist.XXXXXX") || return 1
  for i in "${!_dirhist_e_dir[@]}"; do
    d="${_dirhist_e_dir[i]}"
    if [[ "$d" == "$dir" && "$seen" -lt "$drop" ]]; then
      seen=$((seen + 1))
      continue
    fi
    _dirhist_write_entry "$tmp" "$d" \
      "${_dirhist_e_date[i]}" "${_dirhist_e_time[i]}" "${_dirhist_e_cmd[i]}"
  done
  mv -f -- "$tmp" "$DIRHIST_HISTORY" || {
    rm -f -- "$tmp"
    return 1
  }
  chmod 600 "$DIRHIST_HISTORY" 2>/dev/null || true
}

_dirhist_matches_histignore() {
  local cmd="$1" pat
  local IFS=':'
  local -a pats=()
  [[ -n "${HISTIGNORE:-}" ]] || return 1
  read -ra pats <<< "$HISTIGNORE"
  for pat in "${pats[@]}"; do
    [[ -z "$pat" || "$pat" == "&" ]] && continue
    # Right-hand side is a glob, anchored to the whole command, like HISTIGNORE.
    # shellcheck disable=SC2053 # HISTIGNORE patterns are globs and must stay unquoted.
    if [[ "$cmd" == $pat ]]; then
      return 0
    fi
  done
  return 1
}

# `ls` is in HISTIGNORE, but an alias can make BASH_COMMAND `lsd`.
# Print the typed name when that name is ignored and its alias value is $1.
_dirhist_aliased_histignore_name() {
  local expanded="$1" pat raw val
  local IFS=':'
  local -a pats=()
  [[ -n "${HISTIGNORE:-}" ]] || return 1
  read -ra pats <<< "$HISTIGNORE"
  for pat in "${pats[@]}"; do
    [[ -z "$pat" || "$pat" == "&" || "$pat" == *[*?[]* ]] && continue
    raw=$(builtin alias "$pat" 2>/dev/null) || continue
    val=${raw#alias "$pat"=}
    val=${val#\'}
    val=${val%\'}
    val=${val#\"}
    val=${val%\"}
    if [[ "$expanded" == "$val" ]]; then
      builtin printf '%s\n' "$pat"
      return 0
    fi
  done
  return 1
}

# Sets _dirhist_cmd and _dirhist_log_this.
# New history entries keep the full line (pipelines, &&, newlines).
# HISTIGNORE lines never reach history, so those fall back to BASH_COMMAND.
# A leading space (ignorespace) is not recorded.
_dirhist_capture() {
  local hist_line hist_num prev_cmd
  _dirhist_cmd=
  _dirhist_log_this=0

  hist_line=$(HISTTIMEFORMAT='' builtin history 1 2>/dev/null || true)
  hist_num=$(builtin printf '%s\n' "$hist_line" | sed -n '1s/^ *\([0-9][0-9]*\).*/\1/p')
  prev_cmd=$(builtin printf '%s\n' "$hist_line" | sed '1s/^ *[0-9][0-9]*[* ] //')

  if [[ -n "$hist_num" && "$hist_num" != "${_dirhist_last_histnum:-}" ]]; then
    _dirhist_cmd=$prev_cmd
    _dirhist_log_this=1
    return 0
  fi

  # Not stored in shell history: HISTIGNORE, an alias of a HISTIGNORE name,
  # ignoredups, or a leading space. A leading space stays out of this file.
  local typed
  if _dirhist_matches_histignore "$BASH_COMMAND"; then
    _dirhist_cmd=$BASH_COMMAND
    _dirhist_log_this=1
    return 0
  fi
  if typed=$(_dirhist_aliased_histignore_name "$BASH_COMMAND"); then
    _dirhist_cmd=$typed
    _dirhist_log_this=1
    return 0
  fi
  if [[ -n "$prev_cmd" && "$BASH_COMMAND" == "$prev_cmd" ]]; then
    _dirhist_cmd=$BASH_COMMAND
    _dirhist_log_this=1
    return 0
  fi

  return 0
}

_dirhist_sync_histnum() {
  local hist_line hist_num
  hist_line=$(HISTTIMEFORMAT='' builtin history 1 2>/dev/null || true)
  hist_num=$(builtin printf '%s\n' "$hist_line" | sed -n '1s/^ *\([0-9][0-9]*\).*/\1/p')
  _dirhist_last_histnum=${hist_num:-0}
}

_dirhist_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  builtin printf '%s\n' "$s"
}

# Print "global" or a physical directory for a config section header.
# Return 1 when the line is not a header.
_dirhist_config_header() {
  local line="$1" path home_short='~'
  [[ "$line" == \[*\] ]] || return 1
  case "$line" in
    "[options]")
      builtin printf '%s\n' options
      return 0
      ;;
    "[global]")
      builtin printf '%s\n' global
      return 0
      ;;
  esac
  path=""
  if [[ "$line" =~ ^\[dir[[:space:]]+(.+)\]$ ]]; then
    path="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\[(.+)\]$ ]]; then
    path="${BASH_REMATCH[1]}"
    [[ "$path" == /* || "$path" == "$home_short" || "$path" == "$home_short/"* ]] || return 1
  else
    return 1
  fi
  path=$(_dirhist_trim "$path")
  if [[ "$path" == \"*\" || "$path" == \'*\' ]]; then
    path="${path:1:${#path}-2}"
  fi
  if [[ "$path" == "$home_short" ]]; then
    path="$HOME"
  elif [[ "$path" == "$home_short/"* ]]; then
    path="${HOME}/${path:2}"
  fi
  if [[ -d "$path" ]]; then
    path=$(builtin cd "$path" && builtin pwd -P)
  fi
  builtin printf '%s\n' "$path"
}

# Print the last value of a key under [options], or above the first section.
_dirhist_config_value() {
  local name="$1" line trimmed header scope="" key found=""
  [[ -f "${DIRHIST_CONFIG:-}" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if header=$(_dirhist_config_header "$trimmed"); then
      scope=$header
      continue
    fi
    [[ -z "$scope" || "$scope" == "options" ]] || continue
    if [[ "$trimmed" =~ ^([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(=|[[:space:]])[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1],,}"
      [[ "$key" == "$name" ]] || continue
      found=$(_dirhist_trim "${BASH_REMATCH[3]}")
      if [[ "$found" == \"*\" || "$found" == \'*\' ]]; then
        found="${found:1:${#found}-2}"
      fi
      found="${found,,}"
    fi
  done < "$DIRHIST_CONFIG"
  builtin printf '%s\n' "$found"
}

# Return 0 when a config option is on. Missing keys default to on.
_dirhist_option_on() {
  local val
  val=$(_dirhist_config_value "$1")
  case "$val" in
    off|no|false|0) return 1 ;;
    *) return 0 ;;
  esac
}

_dirhist_theme_names() {
  builtin printf '%s\n' crimson ocean forest amber violet
}

_dirhist_theme_known() {
  local name="$1" one
  while IFS= read -r one; do
    [[ "$one" == "$name" ]] && return 0
  done < <(_dirhist_theme_names)
  return 1
}

# Return 1 when the name is empty or unknown.
_dirhist_theme_resolve() {
  local name="$1"
  _dirhist_theme_known "$name" || return 1
  builtin printf '%s\n' "$name"
}

# Print the selected theme. Unknown or empty values use crimson.
_dirhist_theme_name() {
  local name resolved
  name=$(_dirhist_config_value theme)
  name="${name//[[:space:]]/}"
  if resolved=$(_dirhist_theme_resolve "$name"); then
    builtin printf '%s\n' "$resolved"
  else
    builtin printf '%s\n' crimson
  fi
}

# Set mark, datec, timec, and cmdc for a theme. The caller declares them.
# shellcheck disable=SC2034
_dirhist_theme_codes() {
  case "$1" in
    crimson)
      mark=$'\033[31m'
      datec=$'\033[90m'
      timec=$'\033[38;5;248m'
      cmdc=$'\033[33m'
      ;;
    ocean)
      mark=$'\033[36m'
      datec=$'\033[34m'
      timec=$'\033[96m'
      cmdc=$'\033[97m'
      ;;
    forest)
      mark=$'\033[32m'
      datec=$'\033[90m'
      timec=$'\033[92m'
      cmdc=$'\033[37m'
      ;;
    amber)
      mark=$'\033[38;5;208m'
      datec=$'\033[38;5;130m'
      timec=$'\033[38;5;214m'
      cmdc=$'\033[38;5;223m'
      ;;
    violet)
      mark=$'\033[35m'
      datec=$'\033[38;5;60m'
      timec=$'\033[95m'
      cmdc=$'\033[38;5;189m'
      ;;
    *)
      return 1
      ;;
  esac
}

# $1 theme  $2 number  $3 date  $4 time  $5 command  $6 1 to color
_dirhist_theme_paint() {
  local theme="$1" n="$2" date="$3" time="$4" cmd="$5" colored="$6"
  local mark datec timec cmdc
  _dirhist_theme_codes "$theme" || return 1
  if [[ "$colored" == 1 ]]; then
    builtin printf '%5d  %s[%s%s%s]=[%s%s%s]──►%s %s\033[0m\n' \
      "$n" "$mark" "$datec" "$date" "$mark" "$timec" "$time" "$mark" "$cmdc" "$cmd"
  else
    builtin printf '%5d  [%s]=[%s]──► %s\n' "$n" "$date" "$time" "$cmd"
  fi
}

# $1 label  $2 value  $3 1 to color.
# on is green, off is red, history and config are solarized dark.
# The value stays the terminal's normal color.
_dirhist_status_line() {
  local label="$1" value="$2" colored="$3" labelc
  if [[ "$colored" != 1 ]]; then
    builtin printf '%-8s %s\n' "$label" "$value"
    return 0
  fi
  case "$label" in
    on) labelc=$'\033[32m' ;;
    off) labelc=$'\033[31m' ;;
    *) labelc="$_DIRHIST_SOL_BASE0" ;;
  esac
  builtin printf '%s%-8s\033[0m %s\n' "$labelc" "$label" "$value"
}

# max_lines in a directory section is a limit, not an ignore pattern.
_dirhist_is_max_lines() {
  local key
  [[ "$1" =~ ^([A-Za-z][A-Za-z0-9_]*)[[:space:]]*(=|[[:space:]])[[:space:]]*(.*)$ ]] || return 1
  key="${BASH_REMATCH[1],,}"
  [[ "$key" == max_lines ]]
}

# Return 0 when pat ignores cmd.
# `ls` ignores `ls`, `ls -alh`, and `ls /tmp`. It does not ignore `lsblk`.
# * and ? still match any text.
# shellcheck disable=SC2053
_dirhist_pattern_matches() {
  local cmd="$1" pat="$2"
  [[ "$cmd" == $pat ]] && return 0
  [[ "$cmd" == "$pat "* ]] && return 0
  return 1
}

# Return 0 when cmd must not be written to the shared history.
_dirhist_ignored() {
  local dir="$1" cmd="$2" line trimmed header scope=""
  [[ -n "$cmd" && -f "${DIRHIST_CONFIG:-}" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if header=$(_dirhist_config_header "$trimmed"); then
      scope=$header
      continue
    fi
    _dirhist_is_max_lines "$trimmed" && continue
    # Lines before the first section are global.
    if [[ -z "$scope" || "$scope" == "global" || "$scope" == "$dir" ]]; then
      _dirhist_pattern_matches "$cmd" "$trimmed" && return 0
    fi
  done < "$DIRHIST_CONFIG"
  return 1
}

_dirhist_section_has() {
  local scope="$1" pat="$2" line trimmed header cur="" effective
  [[ -f "${DIRHIST_CONFIG:-}" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if header=$(_dirhist_config_header "$trimmed"); then
      cur=$header
      continue
    fi
    effective="${cur:-global}"
    [[ "$effective" == "$scope" && "$trimmed" == "$pat" ]] && return 0
  done < "$DIRHIST_CONFIG"
  return 1
}

_dirhist_ensure_config() {
  local cfg="$DIRHIST_CONFIG" dir
  [[ -f "$cfg" ]] && return 0
  dir=$(dirname -- "$cfg")
  mkdir -p -- "$dir" || return 1
  cat >| "$cfg" <<'EOF'
# dirhist
# ~/.config/dirhist/config
#
# [options]
# date, color, and status_color accept on or off. All default to on.
# color colors history. status_color colors the on, off, history, and config labels.
# theme is crimson, ocean, forest, amber, or violet. Default is crimson.
# dirhist themes shows a sample of each theme.
# date writes [YYYY-MM-DD]=[HH:MM:SS]──► before each command.
# max_lines is how many commands to keep per directory. Unset means no limit.
# A max_lines line in a directory section overwrites [options].
# off or 0 in that section means no limit for that directory.
#
# A pattern ignores that command and anything after it. ls ignores ls -alh.
# * still matches any text. ls does not ignore lsblk.
# Patterns under [global] are ignored in every recorded directory.
# A [/absolute/path] or [dir /absolute/path] section applies only there.
# Use the physical path (pwd -P). Add a rule with:
#   dirhist ignore ls
#   dirhist ignore -g 'echo *'

[options]
date = on
color = on
status_color = on
theme = crimson

[global]
# git status
# echo *
EOF
}

_dirhist_ignore_list_scope() {
  local want="$1" line trimmed header scope="" any=0 effective
  [[ -f "$DIRHIST_CONFIG" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
    if header=$(_dirhist_config_header "$trimmed"); then
      scope=$header
      continue
    fi
    _dirhist_is_max_lines "$trimmed" && continue
    effective="${scope:-global}"
    if [[ "$effective" == "$want" ]]; then
      builtin printf '  %s\n' "$trimmed"
      any=1
    fi
  done < "$DIRHIST_CONFIG"
  [[ "$any" == 1 ]] || builtin printf '  (none)\n'
}

# scope is "global" or a physical directory path.
_dirhist_ignore_add() {
  local scope="$1" pat="$2" tmp line trimmed header saw=0 added=0
  [[ -n "$pat" ]] || {
    builtin printf 'dirhist: missing pattern\n' >&2
    return 2
  }
  _dirhist_ensure_config || return 1
  if _dirhist_section_has "$scope" "$pat"; then
    builtin printf 'dirhist: already ignoring: %s\n' "$pat" >&2
    return 1
  fi
  tmp=$(mktemp) || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    if [[ -n "$trimmed" ]] && header=$(_dirhist_config_header "$trimmed"); then
      if [[ "$saw" == 1 && "$added" == 0 ]]; then
        builtin printf '%s\n\n' "$pat" >> "$tmp"
        added=1
      fi
      if [[ "$header" == "$scope" ]]; then
        saw=1
      else
        saw=0
      fi
    fi
    builtin printf '%s\n' "$line" >> "$tmp"
  done < "$DIRHIST_CONFIG"
  if [[ "$added" == 0 ]]; then
    if [[ "$saw" == 1 ]]; then
      builtin printf '%s\n' "$pat" >> "$tmp"
    elif [[ "$scope" == "global" ]]; then
      builtin printf '[global]\n%s\n' "$pat" >> "$tmp"
    else
      builtin printf '\n[dir %s]\n%s\n' "$scope" "$pat" >> "$tmp"
    fi
  fi
  mv "$tmp" "$DIRHIST_CONFIG" || {
    rm -f "$tmp"
    return 1
  }
}

# Remove one exact pattern from a scope. Preamble lines count as global.
_dirhist_ignore_del() {
  local scope="$1" pat="$2" tmp line trimmed header cur="" removed=0 effective
  [[ -n "$pat" ]] || {
    builtin printf 'dirhist: missing pattern\n' >&2
    return 2
  }
  [[ -f "$DIRHIST_CONFIG" ]] || {
    builtin printf 'dirhist: not ignoring: %s\n' "$pat" >&2
    return 1
  }
  tmp=$(mktemp) || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed=$(_dirhist_trim "$line")
    if [[ -n "$trimmed" ]] && header=$(_dirhist_config_header "$trimmed"); then
      cur=$header
      builtin printf '%s\n' "$line" >> "$tmp"
      continue
    fi
    effective="${cur:-global}"
    if [[ -n "$trimmed" && "$trimmed" != \#* && "$effective" == "$scope" && "$trimmed" == "$pat" ]]; then
      removed=1
      continue
    fi
    builtin printf '%s\n' "$line" >> "$tmp"
  done < "$DIRHIST_CONFIG"
  if [[ "$removed" == 0 ]]; then
    rm -f -- "$tmp"
    builtin printf 'dirhist: not ignoring: %s\n' "$pat" >&2
    return 1
  fi
  mv -f -- "$tmp" "$DIRHIST_CONFIG" || {
    rm -f -- "$tmp"
    return 1
  }
}

_dirhist_ignore_cmd() {
  local global=0 delete=0 here pat
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -g|--global) global=1; shift ;;
      -d|--delete) delete=1; shift ;;
      --) shift; break ;;
      -*)
        builtin printf 'dirhist: unknown ignore option: %s\n' "$1" >&2
        return 2
        ;;
      *) break ;;
    esac
  done
  _dirhist_ensure_config || return 1
  if [[ "$delete" == 1 ]]; then
    if [[ $# -eq 0 ]]; then
      builtin printf 'dirhist: ignore -d needs a pattern\n' >&2
      return 2
    fi
    pat="$*"
    if [[ "$global" == 1 ]]; then
      _dirhist_ignore_del global "$pat" || return 1
    else
      here=$(_dirhist_here) || return 1
      _dirhist_ignore_del "$here" "$pat" || return 1
    fi
    builtin printf 'dirhist: no longer ignoring: %s\n' "$pat"
    return 0
  fi
  if [[ $# -eq 0 ]]; then
    if [[ "$global" == 1 ]]; then
      builtin printf 'global\n'
      _dirhist_ignore_list_scope global
    else
      here=$(_dirhist_here) || return 1
      builtin printf 'config %s\n' "$DIRHIST_CONFIG"
      builtin printf 'global\n'
      _dirhist_ignore_list_scope global
      builtin printf '%s\n' "$here"
      _dirhist_ignore_list_scope "$here"
    fi
    return 0
  fi
  pat="$*"
  if [[ "$global" == 1 ]]; then
    _dirhist_ignore_add global "$pat" || return 1
    builtin printf 'dirhist: ignoring everywhere: %s\n' "$pat"
  else
    here=$(_dirhist_here) || return 1
    _dirhist_ignore_add "$here" "$pat" || return 1
    builtin printf 'dirhist: ignoring in %s: %s\n' "$here" "$pat"
  fi
}

_dirhist_append() {
  local dir="$1" cmd="$2"
  [[ -n "$cmd" && -d "$dir" ]] || return 0
  if _dirhist_ignored "$dir" "$cmd"; then
    return 0
  fi
  _dirhist_ensure_home || return 0
  {
    flock -x 9 || true
    if _dirhist_option_on date; then
      builtin printf '@@ %s\n[%(%F)T]=[%(%T)T]──► %s\n' "$dir" -1 -1 "$cmd" >> "$DIRHIST_HISTORY"
    else
      builtin printf '@@ %s\n%s\n' "$dir" "$cmd" >> "$DIRHIST_HISTORY"
    fi
    _dirhist_trim_unlocked "$dir" || true
  } 9>>"$DIRHIST_LOCK"
}

_dirhist_resolve_dir() {
  local d="$1" canon
  if [[ ! -d "$d" ]]; then
    builtin printf 'dirhist: not a directory: %s\n' "$d" >&2
    return 1
  fi
  canon=$(builtin cd "$d" && builtin pwd -P) || return 1
  builtin printf '%s\n' "$canon"
}

_dirhist_show_history() {
  local dir="$1" limit="${2:-}"
  _dirhist_ensure_home || return 1
  {
    flock -s 9 || true
    if ! _dirhist_render "$dir" "$limit" "" 0; then
      builtin printf 'dirhist: no history in %s\n' "$dir" >&2
      return 1
    fi
  } 9>>"$DIRHIST_LOCK"
}

_dirhist_theme_sample() {
  local theme="$1" current="$2" colored="$3" star=" "
  [[ "$theme" == "$current" ]] && star="*"
  builtin printf '%s %s\n' "$star" "$theme"
  _dirhist_theme_paint "$theme" 1 "2026-11-01" "11:36:44" "echo hello" "$colored"
}

_dirhist_themes_cmd() {
  local want="${1:-}" current="" colored=0 theme resolved
  current=$(_dirhist_theme_name)
  if [[ -t 1 ]]; then
    colored=1
  fi
  if [[ $# -gt 1 ]]; then
    builtin printf 'dirhist: themes takes one name, or none to show all\n' >&2
    return 2
  fi
  if [[ -n "$want" ]]; then
    want="${want,,}"
    if ! resolved=$(_dirhist_theme_resolve "$want"); then
      builtin printf 'dirhist: unknown theme: %s\n' "$want" >&2
      builtin printf 'themes: %s\n' "$(_dirhist_theme_names | tr '\n' ' ')" >&2
      return 2
    fi
    _dirhist_theme_sample "$resolved" "$current" "$colored"
    builtin printf '\n'
  else
    while IFS= read -r theme; do
      _dirhist_theme_sample "$theme" "$current" "$colored"
      builtin printf '\n'
    done < <(_dirhist_theme_names)
  fi
  if ! _dirhist_option_on color; then
    builtin printf 'color is off. Set color = on in %s to color history.\n' "$DIRHIST_CONFIG"
  fi
  if ! _dirhist_option_on status_color; then
    builtin printf 'status_color is off. Set status_color = on in %s to color the on, off, history, and config labels.\n' "$DIRHIST_CONFIG"
  fi
}

_dirhist_history_cmd() {
  local limit="" dir
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
          builtin printf 'dirhist: history -n needs a number\n' >&2
          return 2
        fi
        limit=$2
        shift 2
        ;;
      -n*)
        limit="${1#-n}"
        if [[ ! "$limit" =~ ^[0-9]+$ ]]; then
          builtin printf 'dirhist: history -n needs a number\n' >&2
          return 2
        fi
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        builtin printf 'dirhist: unknown history option: %s\n' "$1" >&2
        return 2
        ;;
      *) break ;;
    esac
  done
  if [[ $# -eq 0 ]]; then
    dir=$(_dirhist_here) || return 1
  elif [[ $# -eq 1 ]] && _dirhist_is_index "$1"; then
    dir=$(_dirhist_dir_by_number "$1") || return 1
  else
    dir=$(_dirhist_resolve_dir "$*") || return 1
  fi
  _dirhist_show_history "$dir" "$limit"
}

_dirhist_grep_cmd() {
  local all=0 dir pat="" word
  local -a excludes=() includes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--all)
        all=1
        shift
        ;;
      -v|--invert-match|-av|-va)
        [[ "$1" == -av || "$1" == -va ]] && all=1
        shift
        if [[ $# -gt 0 && "$1" == "--" ]]; then
          shift
        fi
        if [[ $# -eq 0 ]]; then
          builtin printf 'dirhist: grep -v needs a pattern\n' >&2
          return 2
        fi
        excludes+=("$1")
        shift
        ;;
      --)
        shift
        includes+=("$@")
        break
        ;;
      -*)
        builtin printf 'dirhist: unknown grep option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        includes+=("$1")
        shift
        ;;
    esac
  done
  if [[ ${#includes[@]} -eq 0 && ${#excludes[@]} -eq 0 ]]; then
    builtin printf 'dirhist: grep needs a pattern\n' >&2
    return 2
  fi
  for word in "${includes[@]}"; do
    if [[ -z "$pat" ]]; then
      pat="$word"
    else
      pat+=" $word"
    fi
  done
  _dirhist_ensure_home || return 1
  {
    flock -s 9 || true
    if [[ "$all" == 1 ]]; then
      if ! _dirhist_render "" "" "$pat" 1 excludes; then
        builtin printf 'dirhist: no matches\n' >&2
        return 1
      fi
    else
      dir=$(_dirhist_here) || return 1
      if ! _dirhist_render "$dir" "" "$pat" 0 excludes; then
        builtin printf 'dirhist: no matches\n' >&2
        return 1
      fi
    fi
  } 9>>"$DIRHIST_LOCK"
}

# Delete one directory's commands. No directory means the current one.
# -n N keeps that directory's newest N commands.
_dirhist_clean_cmd() {
  local keep="" dir total=0 drop=0 kept=0 seen=0 i tmp
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
          builtin printf 'dirhist: clean -n needs a number\n' >&2
          return 2
        fi
        keep=$2
        shift 2
        ;;
      -n*)
        keep="${1#-n}"
        if [[ ! "$keep" =~ ^[0-9]+$ ]]; then
          builtin printf 'dirhist: clean -n needs a number\n' >&2
          return 2
        fi
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        builtin printf 'dirhist: unknown clean option: %s\n' "$1" >&2
        return 2
        ;;
      *) break ;;
    esac
  done
  if [[ $# -eq 0 ]]; then
    dir=$(_dirhist_here) || return 1
  elif [[ $# -eq 1 ]] && _dirhist_is_index "$1"; then
    dir=$(_dirhist_dir_by_number "$1") || return 1
  else
    dir=$(_dirhist_resolve_remove_dir "$*") || return 1
  fi
  _dirhist_ensure_home || return 1
  {
    flock -x 9 || true
    _dirhist_load_entries
    for i in "${!_dirhist_e_dir[@]}"; do
      [[ "${_dirhist_e_dir[i]}" == "$dir" ]] && total=$((total + 1))
    done
    if (( total == 0 )); then
      builtin printf 'dirhist: no commands to remove from %s\n' "$dir"
      return 0
    fi
    if [[ -z "$keep" || "$keep" -eq 0 ]]; then
      drop=$total
    elif (( keep < total )); then
      drop=$((total - keep))
    fi
    kept=$((total - drop))
    if (( drop == 0 )); then
      builtin printf 'dirhist: kept %s commands in %s\n' "$kept" "$dir"
      return 0
    fi
    tmp=$(mktemp "$(dirname -- "$DIRHIST_HISTORY")/.dirhist.XXXXXX") || return 1
    for i in "${!_dirhist_e_dir[@]}"; do
      if [[ "${_dirhist_e_dir[i]}" == "$dir" ]]; then
        if (( seen < drop )); then
          seen=$((seen + 1))
          continue
        fi
      fi
      _dirhist_write_entry "$tmp" "${_dirhist_e_dir[i]}" \
        "${_dirhist_e_date[i]}" "${_dirhist_e_time[i]}" "${_dirhist_e_cmd[i]}"
    done
    mv -f -- "$tmp" "$DIRHIST_HISTORY" || {
      rm -f -- "$tmp"
      return 1
    }
    chmod 600 "$DIRHIST_HISTORY" 2>/dev/null || true
    if (( kept == 0 )); then
      builtin printf 'dirhist: removed %s commands from %s\n' "$total" "$dir"
    else
      builtin printf 'dirhist: removed %s commands from %s, kept %s\n' "$drop" "$dir" "$kept"
    fi
  } 9>>"$DIRHIST_LOCK"
}

_dirhist_prune_cmd() {
  local tmp line removed=0
  if [[ $# -gt 0 ]]; then
    builtin printf 'dirhist: prune takes no arguments\n' >&2
    return 2
  fi
  _dirhist_ensure_home || return 1
  [[ -f "$DIRHIST_REGISTRY" ]] || {
    builtin printf 'dirhist: nothing to prune\n'
    return 0
  }
  tmp=$(mktemp "$(dirname -- "$DIRHIST_REGISTRY")/.dirhist.XXXXXX") || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ -d "$line" ]]; then
      builtin printf '%s\n' "$line" >> "$tmp"
    else
      builtin printf 'dirhist: pruned %s\n' "$line"
      removed=1
    fi
  done < "$DIRHIST_REGISTRY"
  if [[ "$removed" == 0 ]]; then
    rm -f -- "$tmp"
    builtin printf 'dirhist: nothing to prune\n'
    return 0
  fi
  mv -f -- "$tmp" "$DIRHIST_REGISTRY" || {
    rm -f -- "$tmp"
    return 1
  }
  chmod 600 "$DIRHIST_REGISTRY" 2>/dev/null || true
}

_dirhist_init() {
  if [[ -f "$DIRHIST_CONFIG" ]]; then
    builtin printf 'dirhist: config already exists: %s\n' "$DIRHIST_CONFIG"
    return 0
  fi
  _dirhist_ensure_config || return 1
  builtin printf 'dirhist: created %s\n' "$DIRHIST_CONFIG"
}

_dirhist_debug() {
  local was_armed="${_dirhist_armed:-0}"

  if declare -F _dirhist_previous_debug >/dev/null 2>&1; then
    _dirhist_previous_debug || true
  fi

  # Tab-completion runs commands through DEBUG. Stay armed for the real command.
  if [[ -n "${COMP_LINE:-}" ]]; then
    return 0
  fi
  [[ "$was_armed" == 1 ]] || return 0
  _dirhist_armed=0

  _dirhist_capture
  _dirhist_pending_pwd="$(_dirhist_here)"
  _dirhist_pending_cmd=
  _dirhist_pending_wrote=

  if [[ "${_dirhist_log_this:-0}" == 1 && -n "${_dirhist_cmd:-}" ]]; then
    _dirhist_pending_cmd="$_dirhist_cmd"
    if _dirhist_registered "$_dirhist_pending_pwd"; then
      _dirhist_append "$_dirhist_pending_pwd" "$_dirhist_pending_cmd"
      _dirhist_pending_wrote="$_dirhist_pending_pwd"
    fi
  fi
  return 0
}

# Runs at the end of PROMPT_COMMAND, after the command has finished.
# If the command entered a recorded directory, copy it into that directory too.
_dirhist_precmd() {
  local now
  now=$(_dirhist_here)
  if [[ -n "${_dirhist_pending_cmd:-}" && -n "${_dirhist_pending_pwd:-}" && "$now" != "$_dirhist_pending_pwd" ]]; then
    if [[ "$now" != "${_dirhist_pending_wrote:-}" ]] && _dirhist_registered "$now"; then
      _dirhist_append "$now" "$_dirhist_pending_cmd"
    fi
  fi
  _dirhist_pending_cmd=
  _dirhist_sync_histnum
  _dirhist_armed=1
  return 0
}

# Bat's Solarized (dark) bash colors: command yellow, flags blue,
# brackets and pipes green, other words base0.
_DIRHIST_BAT_YELLOW=$'\033[38;2;181;137;0m'
_DIRHIST_BAT_BLUE=$'\033[38;2;38;139;210m'
_DIRHIST_BAT_GREEN=$'\033[38;2;133;153;0m'
_DIRHIST_BAT_BASE0=$'\033[38;2;131;148;150m'

# $1 output name  $2 color name  $3 SGR  $4 text
_dirhist_help_emit() {
  local -n _out="$1"
  local -n _col="$2"
  local c="$3" text="$4"
  [[ -n "$text" ]] || return 0
  if [[ "$c" == "$_col" ]]; then
    _out+="$text"
  else
    [[ -n "$_col" ]] && _out+=$'\033[0m'
    _out+="$c$text"
    _col=$c
  fi
}

# Color one help usage line the way bat --theme='Solarized (dark)' -l bash does.
_dirhist_help_paint() {
  local s="$1" ch word ws
  local help_out="" help_color=""
  local i=0 expect=1 depth=0
  local n=${#s}
  while (( i < n )); do
    ch="${s:i:1}"
    if [[ "$ch" == " " || "$ch" == $'\t' ]]; then
      ws=""
      while (( i < n )); do
        ch="${s:i:1}"
        [[ "$ch" == " " || "$ch" == $'\t' ]] || break
        ws+="$ch"
        i=$((i + 1))
      done
      # bat colors the space before a flag with the flag.
      if (( depth == 0 && i < n )) && [[ "${s:i:1}" == "-" ]]; then
        _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_BLUE" "$ws"
      else
        _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_BASE0" "$ws"
      fi
      continue
    fi
    if [[ "$ch" == "|" || "$ch" == "[" || "$ch" == "]" ]]; then
      _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_GREEN" "$ch"
      if [[ "$ch" == "|" ]]; then
        expect=1
      elif [[ "$ch" == "[" ]]; then
        depth=$((depth + 1))
      elif (( depth > 0 )); then
        depth=$((depth - 1))
      fi
      i=$((i + 1))
      continue
    fi
    if (( expect == 1 && depth == 0 )); then
      word=""
      while (( i < n )); do
        ch="${s:i:1}"
        [[ "$ch" == " " || "$ch" == $'\t' || "$ch" == "|" || "$ch" == "[" || "$ch" == "]" ]] && break
        word+="$ch"
        i=$((i + 1))
      done
      _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_YELLOW" "$word"
      expect=0
      continue
    fi
    if [[ "$ch" == "-" && "$depth" -eq 0 ]]; then
      word=""
      while (( i < n )); do
        ch="${s:i:1}"
        [[ "$ch" == " " || "$ch" == $'\t' || "$ch" == "|" || "$ch" == "[" || "$ch" == "]" ]] && break
        word+="$ch"
        i=$((i + 1))
      done
      _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_BLUE" "$word"
      continue
    fi
    word=""
    while (( i < n )); do
      ch="${s:i:1}"
      [[ "$ch" == " " || "$ch" == $'\t' || "$ch" == "|" || "$ch" == "[" || "$ch" == "]" ]] && break
      word+="$ch"
      i=$((i + 1))
    done
    _dirhist_help_emit help_out help_color "$_DIRHIST_BAT_BASE0" "$word"
  done
  [[ -n "$help_color" ]] && help_out+=$'\033[0m'
  builtin printf '%s' "$help_out"
}

_dirhist_help_row() {
  local cmd="$1" text="$2" painted width spaces
  if [[ -t 1 && -z "${NO_COLOR:-}" && -n "$cmd" ]]; then
    painted=$(_dirhist_help_paint "$cmd")
    width=${#cmd}
    if (( width < 34 )); then
      spaces=$((34 - width))
    else
      spaces=0
    fi
    builtin printf '%s%*s %s\n' "$painted" "$spaces" "" "$text"
    return 0
  fi
  builtin printf '%-34s %s\n' "$cmd" "$text"
}

_dirhist_help() {
  _dirhist_help_row "dirhist" "show this directory's history"
  _dirhist_help_row "dirhist history [-n N] [dir|N]" "show this directory's history, or dir's"
  _dirhist_help_row "" "-n N shows the newest N commands"
  _dirhist_help_row "dirhist on|start [dir|N]" "record this directory, or directory N"
  _dirhist_help_row "dirhist off|stop [dir|N]" "stop recording this directory, or directory N, and keep its commands"
  _dirhist_help_row "dirhist rm|remove [dir|N]" "remove dir from the list and delete its commands"
  _dirhist_help_row "dirhist ls|list" "list numbered directories, marked on or off"
  _dirhist_help_row "dirhist status" "show on or off, the history file, and the config"
  _dirhist_help_row "dirhist grep [-a] [-v PAT] [PAT]" "search this directory's history"
  _dirhist_help_row "" "-a searches every directory."
  _dirhist_help_row "" "-v PAT without another PAT only excludes PAT"
  _dirhist_help_row "" "PAT keeps commands that contain it."
  _dirhist_help_row "" "The flags and PAT can be in either order"
  _dirhist_help_row "dirhist themes [name]" "show a sample of each color theme"
  _dirhist_help_row "dirhist init" "create the config file if it is missing"
  _dirhist_help_row "dirhist ignore" "show ignore rules for this directory"
  _dirhist_help_row "dirhist ignore PAT" "ignore PAT in this directory"
  _dirhist_help_row "dirhist ignore -d PAT" "stop ignoring PAT in this directory"
  _dirhist_help_row "dirhist ignore -g PAT" "ignore PAT in every recorded directory"
  _dirhist_help_row "dirhist ignore -g -d PAT" "stop ignoring PAT everywhere"
  _dirhist_help_row "dirhist prune" "drop recorded directories that are gone"
  _dirhist_help_row "dirhist clean [-n N] [dir|N]" "delete this directory's commands, or dir's"
  _dirhist_help_row "" "-n N keeps the newest N commands"
  _dirhist_help_row "dirhist version|-V|--version" "print version"
  builtin printf '\n'
  builtin printf '%s\n' "Recorded directories are listed in ~/.dirhist."
  builtin printf '%s\n' "dirhist list prints a number for each one. history, on, off, clean, and rm use that number."
  builtin printf '%s\n' "on and off with no number use the current directory."
  builtin printf '%s\n' "Commands are appended to ~/.dirhist_history as soon as they run."
  builtin printf '%s\n' "Each directory's commands stay separate in that file. cd is included."
  builtin printf '%s\n' "date, color, and status_color are on or off under [options]."
  builtin printf '%s\n' "max_lines is how many commands to keep per directory. Unset means no limit."
  builtin printf '%s\n' "A max_lines line in a directory section overwrites [options]. off or 0 means no limit there."
  builtin printf '%s\n' "theme is crimson, ocean, forest, amber, or violet. Default is crimson."
  builtin printf '%s\n' "Tab completion fills commands, theme names, and recorded directories."
  builtin printf '%s\n' "Ignore rules are stored in the config file."
  builtin printf '%s\n' "Prune removes a directory from the list. Its old commands stay in the history."
  builtin printf '%s\n' "clean deletes this directory's commands. A path or a list number chooses another directory."
  builtin printf '%s\n' "clean -n N keeps the newest N commands there. Other directories stay."
  builtin printf '%s\n' "rm|remove deletes that directory's commands. stop|off keeps them. disable is the same as stop."
}

_dirhist_add() {
  local here="$1"
  if [[ ! -d "$here" ]]; then
    builtin printf 'dirhist: not a directory: %s\n' "$here" >&2
    return 1
  fi
  _dirhist_ensure_home || {
    builtin printf 'dirhist: cannot write %s\n' "$DIRHIST_REGISTRY" >&2
    return 1
  }
  if _dirhist_registered "$here"; then
    builtin printf 'dirhist: already recording %s\n' "$here"
  else
    builtin printf '%s\n' "$here" >> "$DIRHIST_REGISTRY" || return 1
    builtin printf 'dirhist: recording %s\n' "$here"
    # The hook ran before this directory was recorded, so keep the enabling command.
    if [[ -n "${_dirhist_pending_cmd:-}" && "${_dirhist_pending_wrote:-}" != "$here" ]]; then
      _dirhist_append "$here" "$_dirhist_pending_cmd"
      _dirhist_pending_wrote="$here"
    fi
  fi
  builtin printf 'dirhist: appending to %s\n' "$DIRHIST_HISTORY"
}

_dirhist_remove() {
  local here="$1" tmp
  _dirhist_ensure_home || return 1
  if ! _dirhist_registered "$here"; then
    builtin printf 'dirhist: %s is not recorded\n' "$here" >&2
    return 1
  fi
  tmp=$(mktemp "${DIRHIST_REGISTRY}.XXXXXX") || return 1
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$here" ]] && continue
    builtin printf '%s\n' "$line"
  done < "$DIRHIST_REGISTRY" >| "$tmp"
  mv "$tmp" "$DIRHIST_REGISTRY"
  chmod 600 "$DIRHIST_REGISTRY" 2>/dev/null || true
  builtin printf 'dirhist: stopped recording %s\n' "$here"
}

# Use the physical path when the directory exists. A missing directory
# is matched by the path stored in the list.
_dirhist_resolve_remove_dir() {
  local d="$1" home_short='~'
  if [[ -d "$d" ]]; then
    _dirhist_resolve_dir "$d"
    return
  fi
  if [[ "$d" == "$home_short" ]]; then
    d="$HOME"
  elif [[ "$d" == "$home_short/"* ]]; then
    d="${HOME}/${d:2}"
  fi
  builtin printf '%s\n' "$d"
}

# Drop one directory from the list and delete its commands.
_dirhist_forget() {
  local dir="$1" tmp line listed=0 removed=0 i
  _dirhist_ensure_home || return 1
  {
    flock -x 9 || true
    if [[ -f "$DIRHIST_REGISTRY" ]]; then
      tmp=$(mktemp "$(dirname -- "$DIRHIST_REGISTRY")/.dirhist.XXXXXX") || return 1
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$dir" ]]; then
          listed=1
          continue
        fi
        [[ -n "$line" ]] && builtin printf '%s\n' "$line" >> "$tmp"
      done < "$DIRHIST_REGISTRY"
      if [[ "$listed" == 1 ]]; then
        mv -f -- "$tmp" "$DIRHIST_REGISTRY" || {
          rm -f -- "$tmp"
          return 1
        }
        chmod 600 "$DIRHIST_REGISTRY" 2>/dev/null || true
      else
        rm -f -- "$tmp"
      fi
    fi
    _dirhist_load_entries
    for i in "${!_dirhist_e_dir[@]}"; do
      [[ "${_dirhist_e_dir[i]}" == "$dir" ]] && removed=$((removed + 1))
    done
    if [[ "$removed" -gt 0 ]]; then
      tmp=$(mktemp "$(dirname -- "$DIRHIST_HISTORY")/.dirhist.XXXXXX") || return 1
      for i in "${!_dirhist_e_dir[@]}"; do
        [[ "${_dirhist_e_dir[i]}" == "$dir" ]] && continue
        _dirhist_write_entry "$tmp" "${_dirhist_e_dir[i]}" \
          "${_dirhist_e_date[i]}" "${_dirhist_e_time[i]}" "${_dirhist_e_cmd[i]}"
      done
      mv -f -- "$tmp" "$DIRHIST_HISTORY" || {
        rm -f -- "$tmp"
        return 1
      }
      chmod 600 "$DIRHIST_HISTORY" 2>/dev/null || true
    fi
    if [[ "$listed" == 0 && "$removed" == 0 ]]; then
      builtin printf 'dirhist: %s is not recorded\n' "$dir" >&2
      return 1
    fi
    builtin printf 'dirhist: removed %s\n' "$dir"
    builtin printf 'dirhist: deleted %s commands\n' "$removed"
  } 9>>"$DIRHIST_LOCK"
}

# No argument is the current directory. One argument is a list number.
_dirhist_on_off_dir() {
  local cmd="$1"
  shift
  if [[ $# -eq 0 ]]; then
    _dirhist_here
    return
  fi
  if [[ $# -eq 1 ]] && _dirhist_is_index "$1"; then
    _dirhist_dir_by_number "$1"
    return
  fi
  builtin printf 'dirhist: %s takes a directory number, or none for this directory\n' "$cmd" >&2
  return 2
}

_dirhist_remove_cmd() {
  local dir
  if [[ $# -eq 0 ]]; then
    dir=$(_dirhist_here) || return 1
  elif [[ $# -eq 1 ]] && _dirhist_is_index "$1"; then
    dir=$(_dirhist_dir_by_number "$1") || return 1
  else
    dir=$(_dirhist_resolve_remove_dir "$*") || return 1
  fi
  _dirhist_forget "$dir"
}

# A list number is 1, 2, 3, ... with no leading zero.
_dirhist_is_index() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

# Fill _dirhist_dirs and _dirhist_dir_on in the same order as dirhist list.
# on directories come from the registry. off directories still have commands.
_dirhist_load_dir_index() {
  local line dir
  local -A seen=()
  _dirhist_dirs=()
  _dirhist_dir_on=()
  if [[ -f "$DIRHIST_REGISTRY" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      _dirhist_dirs+=("$line")
      _dirhist_dir_on+=("on")
      seen["$line"]=1
    done < "$DIRHIST_REGISTRY"
  fi
  if [[ -f "$DIRHIST_HISTORY" && -e "$DIRHIST_LOCK" ]]; then
    {
      flock -s 9 || true
      _dirhist_load_entries
    } 9>>"$DIRHIST_LOCK"
  elif [[ -f "$DIRHIST_HISTORY" ]]; then
    _dirhist_load_entries
  else
    _dirhist_e_dir=()
  fi
  for dir in "${_dirhist_e_dir[@]}"; do
    [[ -n "$dir" && -z "${seen[$dir]:-}" ]] || continue
    seen["$dir"]=1
    _dirhist_dirs+=("$dir")
    _dirhist_dir_on+=("off")
  done
}

# Print the path for a dirhist list number.
_dirhist_dir_by_number() {
  local n="$1"
  _dirhist_load_dir_index || return 1
  if (( n < 1 || n > ${#_dirhist_dirs[@]} )); then
    builtin printf 'dirhist: no directory numbered %s\n' "$n" >&2
    return 1
  fi
  builtin printf '%s\n' "${_dirhist_dirs[$((n - 1))]}"
}

_dirhist_list() {
  local i n width=1 label use_color=0
  _dirhist_ensure_home || return 1
  _dirhist_load_dir_index || return 1
  if [[ -t 1 ]] && _dirhist_option_on status_color; then
    use_color=1
  fi
  if (( ${#_dirhist_dirs[@]} > 0 )); then
    width=${#_dirhist_dirs[@]}
    width=${#width}
  fi
  for i in "${!_dirhist_dirs[@]}"; do
    n=$((i + 1))
    label="${_dirhist_dir_on[i]}"
    builtin printf '%*d  ' "$width" "$n"
    _dirhist_status_line "$label" "${_dirhist_dirs[i]}" "$use_color"
  done
}

_dirhist_status() {
  local here="$1" label use_color=0
  _dirhist_ensure_home || return 1
  if [[ -t 1 ]] && _dirhist_option_on status_color; then
    use_color=1
  fi
  if _dirhist_registered "$here"; then
    label=on
  else
    label=off
  fi
  _dirhist_status_line "$label" "$here" "$use_color"
  _dirhist_status_line history "$DIRHIST_HISTORY" "$use_color"
  _dirhist_status_line config "$DIRHIST_CONFIG" "$use_color"
}

dirhist() {
  local op="${1:-history}" here
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$op" in
    history)
      _dirhist_history_cmd "$@"
      ;;
    on|start)
      here=$(_dirhist_on_off_dir "$op" "$@") || return
      _dirhist_add "$here"
      ;;
    off|disable|stop)
      here=$(_dirhist_on_off_dir "$op" "$@") || return
      _dirhist_remove "$here"
      ;;
    rm|remove)
      _dirhist_remove_cmd "$@"
      ;;
    list|ls)
      _dirhist_list
      ;;
    status)
      here=$(_dirhist_here) || return 1
      _dirhist_status "$here"
      ;;
    ignore)
      _dirhist_ignore_cmd "$@"
      ;;
    grep)
      _dirhist_grep_cmd "$@"
      ;;
    prune)
      _dirhist_prune_cmd "$@"
      ;;
    clean)
      _dirhist_clean_cmd "$@"
      ;;
    theme|themes)
      _dirhist_themes_cmd "$@"
      ;;
    init)
      if [[ $# -gt 0 ]]; then
        builtin printf 'dirhist: init takes no arguments\n' >&2
        return 2
      fi
      _dirhist_init
      ;;
    help|-h|--help)
      _dirhist_help
      ;;
    version|-V|--version)
      if [[ $# -gt 0 ]]; then
        builtin printf 'dirhist: version takes no arguments\n' >&2
        return 2
      fi
      builtin printf 'dirhist %s\n' "$DIRHIST_VERSION"
      ;;
    *)
      builtin printf 'dirhist: unknown argument: %s\n' "$op" >&2
      _dirhist_help >&2
      return 2
      ;;
  esac
}

_dirhist_install() {
  [[ "${_dirhist_installed:-0}" == 1 ]] && return 0
  case $- in
    *i*) ;;
    *) return 0 ;;
  esac

  _dirhist_ensure_config || true
  _dirhist_ensure_home || true

  local prev body
  prev=$(trap -p DEBUG || true)
  if [[ -n "$prev" && "$prev" != *"_dirhist_debug"* ]]; then
    body=$(builtin printf '%s\n' "$prev" | sed -n "s/^trap -- '\\(.*\\)' DEBUG$/\\1/p")
    if [[ -n "$body" ]]; then
      eval "_dirhist_previous_debug() { ${body}; }"
    fi
  fi
  trap '_dirhist_debug' DEBUG

  if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == declare\ -a* ]]; then
    local item found=0
    for item in "${PROMPT_COMMAND[@]}"; do
      [[ "$item" == "_dirhist_precmd" ]] && found=1
    done
    [[ "$found" == 0 ]] && PROMPT_COMMAND+=("_dirhist_precmd")
  else
    case ";${PROMPT_COMMAND:-};" in
      *";_dirhist_precmd;"*) ;;
      *)
        # shellcheck disable=SC2178,SC2128 # String form. The array form is handled above.
        PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND};}_dirhist_precmd"
        ;;
    esac
  fi

  _dirhist_installed=1
}

# Fill COMPREPLY from a whitespace-separated word list.
_dirhist_complete_words() {
  local word list="$1" cur="$2"
  COMPREPLY=()
  while IFS= read -r word; do
    [[ -n "$word" ]] && COMPREPLY+=("$word")
  done < <(compgen -W "$list" -- "$cur")
}

# Recorded directories first. Other directories when none of those match.
_dirhist_complete_dirs() {
  local cur="$1" line found=0
  COMPREPLY=()
  if [[ -r "${DIRHIST_REGISTRY:-}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      case "$line" in
        "$cur"*)
          COMPREPLY+=("$line")
          found=1
          ;;
      esac
    done < "$DIRHIST_REGISTRY"
  fi
  if [[ "$found" -eq 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && COMPREPLY+=("$line")
    done < <(compgen -d -- "$cur")
  fi
  _dirhist_complete_numbers "$cur"
}

_dirhist_complete_numbers() {
  local cur="$1" i n
  _dirhist_load_dir_index || return 0
  for i in "${!_dirhist_dirs[@]}"; do
    n=$((i + 1))
    if [[ -z "$cur" || "$n" == "$cur"* ]]; then
      COMPREPLY+=("$n")
    fi
  done
}

_dirhist_complete() {
  local cur prev words cword
  if declare -F _init_completion >/dev/null 2>&1; then
    _init_completion || return
  else
    COMPREPLY=()
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
    cur="${COMP_WORDS[cword]}"
    prev="${COMP_WORDS[cword - 1]}"
  fi

  if (( cword <= 1 )); then
    _dirhist_complete_words "on start off stop remove list status history grep themes init ignore prune clean help version -V --version" "$cur"
    return 0
  fi

  case "${words[1]}" in
    history)
      _dirhist_complete_history
      ;;
    rm|remove|on|start|off|stop|disable)
      (( cword == 2 )) || return 0
      _dirhist_complete_dirs "$cur"
      compopt -o filenames 2>/dev/null || true
      ;;
    grep)
      _dirhist_complete_grep
      ;;
    theme|themes)
      (( cword == 2 )) || return 0
      _dirhist_complete_words "$(_dirhist_theme_names | tr '\n' ' ')" "$cur"
      ;;
    ignore)
      if [[ -z "$cur" || "$cur" == -* ]]; then
        _dirhist_complete_words "-g --global -d --delete" "$cur"
      fi
      ;;
    clean)
      _dirhist_complete_history
      ;;
    version|-V|--version)
      return 0
      ;;
  esac
}

_dirhist_complete_history() {
  local i=2 positional=0
  while (( i < cword )); do
    case "${words[i]}" in
      -n)
        i=$((i + 2))
        ;;
      -n*)
        i=$((i + 1))
        ;;
      -*)
        i=$((i + 1))
        ;;
      *)
        positional=1
        i=$((i + 1))
        ;;
    esac
  done
  if [[ "$prev" == -n || "$positional" == 1 ]]; then
    return 0
  fi
  if [[ "$cur" == -* ]]; then
    _dirhist_complete_words "-n" "$cur"
    return 0
  fi
  _dirhist_complete_dirs "$cur"
  if [[ -z "$cur" ]]; then
    COMPREPLY+=("-n")
  fi
  compopt -o filenames 2>/dev/null || true
}

_dirhist_complete_grep() {
  case "$prev" in
    -v|--invert-match|-av|-va)
      return 0
      ;;
  esac
  if [[ -z "$cur" || "$cur" == -* ]]; then
    _dirhist_complete_words "-a --all -v --invert-match -av -va" "$cur"
  fi
}

_dirhist_install
complete -F _dirhist_complete dirhist
