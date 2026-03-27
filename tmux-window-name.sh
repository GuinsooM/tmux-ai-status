#!/bin/bash

pane_pid="$1"
fallback_name="$2"

is_codex_descendant() {
  local cpid gpid

  [ -n "$pane_pid" ] || return 1

  for cpid in $(ps --ppid "$pane_pid" -o pid= 2>/dev/null); do
    if ps -p "$cpid" -o comm= 2>/dev/null | grep -qi '^codex$'; then
      return 0
    fi
    for gpid in $(ps --ppid "$cpid" -o pid= 2>/dev/null); do
      if ps -p "$gpid" -o comm= 2>/dev/null | grep -qi '^codex$'; then
        return 0
      fi
    done
  done

  return 1
}

if [ "$fallback_name" = "node" ] && is_codex_descendant; then
  printf 'codex'
elif [ -n "$fallback_name" ]; then
  printf '%s' "$fallback_name"
else
  printf 'shell'
fi
