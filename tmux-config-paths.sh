#!/bin/bash

tmux_local_candidates() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

  if [ -n "${TMUX_LOCAL:-}" ]; then
    printf '%s\n' "$TMUX_LOCAL"
  fi

  printf '%s\n' \
    "${xdg_config_home}/tmux/tmux.conf.local" \
    "${HOME}/.tmux.conf.local"
}

tmux_config_candidates() {
  local local_path="$1"
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

  if [ -n "${TMUX_CONFIG:-}" ]; then
    printf '%s\n' "$TMUX_CONFIG"
  fi

  case "$local_path" in
    */tmux.conf.local|*/.tmux.conf.local)
      printf '%s\n' "${local_path%.local}"
      ;;
  esac

  printf '%s\n' \
    "${xdg_config_home}/tmux/tmux.conf" \
    "${HOME}/.tmux.conf"
}

resolve_tmux_local() {
  local candidate

  if [ -n "${TMUX_LOCAL:-}" ]; then
    printf '%s\n' "$TMUX_LOCAL"
    return 0
  fi

  while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(tmux_local_candidates)

  return 1
}

resolve_tmux_config() {
  local local_path="$1" candidate

  if [ -n "${TMUX_CONFIG:-}" ]; then
    printf '%s\n' "$TMUX_CONFIG"
    return 0
  fi

  while IFS= read -r candidate; do
    [ -f "$candidate" ] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(tmux_config_candidates "$local_path")

  return 1
}

latest_backup_for() {
  local target="$1"
  local backup

  backup=$(ls -t "${target}.bak."* 2>/dev/null | head -1)
  if [ -n "$backup" ]; then
    printf '%s\n' "$backup"
  fi
}

resolve_tmux_local_from_backups() {
  local candidate backup latest_backup="" latest_target=""

  while IFS= read -r candidate; do
    backup=$(latest_backup_for "$candidate")
    if [ -n "$backup" ] && { [ -z "$latest_backup" ] || [ "$backup" -nt "$latest_backup" ]; }; then
      latest_backup="$backup"
      latest_target="$candidate"
    fi
  done < <(tmux_local_candidates)

  if [ -n "$latest_target" ]; then
    printf '%s\n' "$latest_target"
  fi
}
