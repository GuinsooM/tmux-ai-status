#!/bin/bash
# Unified AI CLI status for tmux.
# Usage: bash tmux-ai-status.sh <pane_pid> [left|right]

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

# --- Find Claude cache files by matching pane cwd ---
find_claude_cache() {
  local side="$1"
  local pane_cwd
  pane_cwd=$(get_pane_cwd)

  # Try to find cache keyed by this cwd
  if [ -n "$pane_cwd" ]; then
    local cwd_hash
    cwd_hash=$(echo -n "$pane_cwd" | md5sum | cut -c1-8)
    if [ "$side" = "left" ]; then
      local f="/tmp/claude-status-left-${USER}-${cwd_hash}.tmux"
      [ -f "$f" ] && cat "$f" && return
    else
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
  fi

  # Fallback: find the most recently modified cache file
  if [ "$side" = "left" ]; then
    ls -t /tmp/claude-status-left-${USER}-*.tmux 2>/dev/null | head -1 | xargs cat 2>/dev/null
  else
    local f
    f=$(ls -t /tmp/claude-status-${USER}-*.tmux 2>/dev/null | grep -v '\-model\.tmux$\|\-usage' | head -1)
    if [ -n "$f" ]; then
      local per_tab usage_shared model_suffix
      per_tab=$(cat "$f")
      usage_shared=$(cat "/tmp/claude-status-usage-${USER}.tmux" 2>/dev/null)
      model_suffix=$(cat "${f%.tmux}-model.tmux" 2>/dev/null)
      echo "${per_tab}${usage_shared}${model_suffix}"
    fi
  fi
}

# --- Build dir + git string ---
build_dir_git() {
  local cwd="$1"
  local out=""
  if [ -n "$cwd" ]; then
    out="#[fg=colour114]$(basename "$cwd")#[default]"
    if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
      local branch dirty=""
      branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
      if [ -n "$branch" ]; then
        if ! git -C "$cwd" diff --quiet --no-optional-locks 2>/dev/null || ! git -C "$cwd" diff --cached --quiet --no-optional-locks 2>/dev/null; then
          dirty="*"
        fi
        out="${out} #[fg=colour33]git:(#[fg=red]${branch}${dirty}#[fg=colour33])#[default]"
      fi
    fi
  fi
  echo "$out"
}

cli=$(detect_cli)

case "$cli" in
  claude)
    if [ "$SIDE" = "left" ]; then
      find_claude_cache "left"
    else
      find_claude_cache "right"
    fi
    ;;
  codex)
    if [ "$SIDE" = "left" ]; then
      pane_cwd=$(get_pane_cwd)
      build_dir_git "$pane_cwd"
    else
      bash "$(dirname "$0")/tmux-codex-status.sh"
    fi
    ;;
  *)
    if [ "$SIDE" = "left" ]; then
      pane_cwd=$(get_pane_cwd)
      build_dir_git "$pane_cwd"
    fi
    # right side: show nothing when no AI CLI is running
    ;;
esac
