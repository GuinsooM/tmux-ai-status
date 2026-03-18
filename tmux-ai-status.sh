#!/bin/bash
# Unified AI CLI status for tmux.
# Usage: bash tmux-ai-status.sh <pane_pid> [left|right]

# --- Pad/truncate tmux-formatted string to fixed visible width ---
# Usage: pad_to <width> <tmux_string>
# Counts only visible chars (skipping #[...] format codes).
# Pads with spaces if short, truncates with … if long.
pad_to() {
  local target_width="$1" str="$2"
  local visible
  visible=$(echo -n "$str" | sed 's/#\[[^]]*\]//g')
  local vlen=${#visible}
  if [ "$vlen" -lt "$target_width" ]; then
    local pad_count=$(( target_width - vlen ))
    printf '%s%*s' "$str" "$pad_count" ""
  elif [ "$vlen" -gt "$target_width" ]; then
    # Truncate: walk through, keep format codes, cut visible chars at limit
    local result="" in_fmt=0 count=0 limit=$(( target_width - 1 ))
    local i char
    for (( i=0; i<${#str}; i++ )); do
      char="${str:$i:1}"
      if [ "$in_fmt" -eq 1 ]; then
        result="${result}${char}"
        [ "$char" = "]" ] && in_fmt=0
      elif [ "$char" = "#" ] && [ "${str:$((i+1)):1}" = "[" ]; then
        result="${result}#"
        in_fmt=1
      else
        if [ "$count" -lt "$limit" ]; then
          result="${result}${char}"
          count=$((count + 1))
        elif [ "$count" -eq "$limit" ]; then
          result="${result}…"
          count=$((count + 1))
        fi
      fi
    done
    printf '%s#[default]' "$result"
  else
    echo -n "$str"
  fi
}

SIDE="${1:-right}"
# Get active pane's PID directly from tmux
PANE_PID=$(tmux display-message -p '#{pane_pid}' 2>/dev/null)

# --- Detect which AI CLI is running ---
detect_cli() {
  [ -z "$PANE_PID" ] && echo "none" && return
  local children
  children=$(ps --ppid "$PANE_PID" -o comm= 2>/dev/null)
  if echo "$children" | grep -qi "claude"; then echo "claude"; return; fi
  if echo "$children" | grep -qi "codex"; then echo "codex"; return; fi
  for cpid in $(ps --ppid "$PANE_PID" -o pid= 2>/dev/null); do
    local gc
    gc=$(ps --ppid "$cpid" -o comm= 2>/dev/null)
    if echo "$gc" | grep -qi "claude"; then echo "claude"; return; fi
    if echo "$gc" | grep -qi "codex"; then echo "codex"; return; fi
  done
  echo "none"
}

# --- Get cwd of the deepest child process in this pane ---
get_pane_cwd() {
  local cwd=""
  for cpid in $(ps --ppid "$PANE_PID" -o pid= 2>/dev/null); do
    cwd=$(readlink -f "/proc/${cpid}/cwd" 2>/dev/null)
    [ -n "$cwd" ] && echo "$cwd" && return
  done
  readlink -f "/proc/${PANE_PID}/cwd" 2>/dev/null
}

# --- Find Claude right-side cache by matching pane cwd ---
find_claude_cache() {
  local pane_cwd
  pane_cwd=$(get_pane_cwd)

  # Try to find cache keyed by this cwd
  if [ -n "$pane_cwd" ]; then
    local cwd_hash
    cwd_hash=$(echo -n "$pane_cwd" | md5sum | cut -c1-8)
    local f="/tmp/claude-status-${USER}-${cwd_hash}.tmux"
    if [ -f "$f" ]; then
      local per_tab usage_shared model_suffix
      per_tab=$(cat "$f")
      usage_shared=$(cat "/tmp/claude-status-usage-${USER}.tmux" 2>/dev/null)
      model_suffix=$(cat "${f%.tmux}-model.tmux" 2>/dev/null)
      echo "${per_tab}${usage_shared}${model_suffix}"
      return
    fi
  fi

  # Fallback: most recently modified cache
  local f
  f=$(ls -t /tmp/claude-status-${USER}-*.tmux 2>/dev/null | grep -v '\-model\.tmux$\|\-usage' | head -1)
  if [ -n "$f" ]; then
    local per_tab usage_shared model_suffix
    per_tab=$(cat "$f")
    usage_shared=$(cat "/tmp/claude-status-usage-${USER}.tmux" 2>/dev/null)
    model_suffix=$(cat "${f%.tmux}-model.tmux" 2>/dev/null)
    echo "${per_tab}${usage_shared}${model_suffix}"
  fi
}

# --- Build dir + git string ---
build_dir_git() {
  local cwd="$1"
  local out=""
  if [ -n "$cwd" ]; then
    local dir_name
    dir_name=$(basename "$cwd")
    out=" #[fg=colour114]${dir_name}#[default]"
    if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
      local branch dirty=""
      branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
      if [ -n "$branch" ]; then
        if ! git -C "$cwd" diff --quiet --no-optional-locks 2>/dev/null || ! git -C "$cwd" diff --cached --quiet --no-optional-locks 2>/dev/null; then
          dirty="*"
        fi
        out="${out} #[fg=red]${branch}${dirty}#[default]"
      fi
    fi
  fi
  echo -n "$out"
}

# --- Right-pad: pad spaces on the LEFT (for right-aligned status) ---
# Usage: rpad_to <width> <tmux_string>
rpad_to() {
  local target_width="$1" str="$2"
  local visible
  visible=$(echo -n "$str" | sed 's/#\[[^]]*\]//g')
  local vlen=${#visible}
  if [ "$vlen" -lt "$target_width" ]; then
    local pad_count=$(( target_width - vlen ))
    printf '%*s%s' "$pad_count" "" "$str"
  else
    echo -n "$str"
  fi
}

# Fixed visible widths (prevents tab/status jumping on tab switch)
LEFT_WIDTH=20
RIGHT_WIDTH=80

cli=$(detect_cli)

# Left side: always real-time dir+branch (never from cache — avoids wrong dir on tab switch)
if [ "$SIDE" = "left" ]; then
  pane_cwd=$(get_pane_cwd)
  pad_to "$LEFT_WIDTH" "$(build_dir_git "$pane_cwd")"
else
  # Right side: CLI-specific status
  case "$cli" in
    claude)
      rpad_to "$RIGHT_WIDTH" "$(find_claude_cache "right")"
      ;;
    codex)
      rpad_to "$RIGHT_WIDTH" "$(bash "$(dirname "$0")/tmux-codex-status.sh")"
      ;;
  esac
fi
