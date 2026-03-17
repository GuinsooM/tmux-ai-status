#!/bin/bash
# install.sh - Install tmux-ai-status into oh-my-tmux configuration
#
# Usage: bash install.sh
#
# What it does:
#   1. Patches tmux.conf.local (oh-my-tmux) to wire up AI status display
#   2. Configures Claude Code's statusline to feed data to tmux
#
# Prerequisites:
#   - oh-my-tmux (https://github.com/gpakosz/.tmux)
#   - jq, git, md5sum
#   - Claude Code (for Claude status) and/or Codex CLI (for Codex status)
#   - Claude HUD plugin (for Claude 5h/7d usage data)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMUX_LOCAL="${HOME}/.config/tmux/tmux.conf.local"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Check prerequisites ---
[ -f "$TMUX_LOCAL" ] || error "oh-my-tmux config not found: $TMUX_LOCAL"
command -v jq >/dev/null 2>&1 || error "jq is required but not installed"
command -v git >/dev/null 2>&1 || error "git is required but not installed"

# --- Backup ---
cp "$TMUX_LOCAL" "${TMUX_LOCAL}.bak.$(date +%Y%m%d%H%M%S)"
info "Backed up tmux.conf.local"

# --- Patch status-left ---
if grep -q 'tmux-ai-status.sh left' "$TMUX_LOCAL" 2>/dev/null; then
  warn "status-left already patched, skipping"
else
  # Find the active tmux_conf_theme_status_left line and replace it
  sed -i '/^tmux_conf_theme_status_left=.*❐.*#S/{
    /tmux-ai-status/!{
      s|.*|tmux_conf_theme_status_left=" ❐ #S \| #(bash '"$SCRIPT_DIR"'/tmux-ai-status.sh left) "|
    }
  }' "$TMUX_LOCAL"
  info "Patched status-left"
fi

# --- Patch status-left style (2 segments: session + dir/git) ---
if grep -q 'tmux_conf_theme_status_left_fg=.*colour_6.*colour_3' "$TMUX_LOCAL" 2>/dev/null; then
  warn "status-left style already patched, skipping"
else
  sed -i 's/^tmux_conf_theme_status_left_fg=.*/tmux_conf_theme_status_left_fg="$tmux_conf_theme_colour_6,$tmux_conf_theme_colour_3"/' "$TMUX_LOCAL"
  sed -i 's/^tmux_conf_theme_status_left_bg=.*/tmux_conf_theme_status_left_bg="$tmux_conf_theme_colour_9,$tmux_conf_theme_colour_1"/' "$TMUX_LOCAL"
  sed -i 's/^tmux_conf_theme_status_left_attr=.*/tmux_conf_theme_status_left_attr="bold,none"/' "$TMUX_LOCAL"
  info "Patched status-left style"
fi

# --- Patch status-right ---
if grep -q 'tmux-ai-status.sh right' "$TMUX_LOCAL" 2>/dev/null; then
  warn "status-right already patched, skipping"
else
  sed -i '/^tmux_conf_theme_status_right=.*prefix.*mouse/{
    /tmux-ai-status/!{
      s|.*|tmux_conf_theme_status_right=" #{prefix}#{mouse}#{pairing}#{synchronized}#(bash '"$SCRIPT_DIR"'/tmux-ai-status.sh right) "|
    }
  }' "$TMUX_LOCAL"
  info "Patched status-right"
fi

# --- Patch status-right style (1 segment, dark background) ---
if grep -q 'tmux_conf_theme_status_right_fg=.*colour_12"$' "$TMUX_LOCAL" 2>/dev/null; then
  warn "status-right style already patched, skipping"
else
  sed -i 's/^tmux_conf_theme_status_right_fg=.*/tmux_conf_theme_status_right_fg="$tmux_conf_theme_colour_12"/' "$TMUX_LOCAL"
  sed -i 's/^tmux_conf_theme_status_right_bg=.*/tmux_conf_theme_status_right_bg="$tmux_conf_theme_colour_1"/' "$TMUX_LOCAL"
  sed -i 's/^tmux_conf_theme_status_right_attr=.*/tmux_conf_theme_status_right_attr="none"/' "$TMUX_LOCAL"
  info "Patched status-right style"
fi

# --- Add hooks for window switch refresh ---
if grep -q 'tmux-ai-status-hook.sh' "$TMUX_LOCAL" 2>/dev/null; then
  warn "Hooks already configured, skipping"
else
  # Insert before the tpm section
  sed -i '/^# -- tpm/i\
# Refresh AI status on window/pane focus change\
set-hook -g pane-focus-in "run-shell '"'"'bash '"$SCRIPT_DIR"'/tmux-ai-status-hook.sh'"'"'"\
set-hook -g window-linked "run-shell '"'"'bash '"$SCRIPT_DIR"'/tmux-ai-status-hook.sh'"'"'"\
' "$TMUX_LOCAL"
  info "Added pane-focus hooks"
fi

# --- Configure Claude Code statusline ---
if [ -f "$CLAUDE_SETTINGS" ]; then
  if grep -q 'tmux-claude-status.sh' "$CLAUDE_SETTINGS" 2>/dev/null; then
    warn "Claude Code statusline already configured, skipping"
  else
    # Use jq to update settings.json
    tmp=$(mktemp)
    jq '.statusLine = {"type": "command", "command": "bash '"$SCRIPT_DIR"'/tmux-claude-status.sh"}' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    info "Configured Claude Code statusline"
  fi
else
  warn "Claude Code settings not found at $CLAUDE_SETTINGS, skip statusline config"
  warn "Manually add to your Claude Code settings.json:"
  echo '  "statusLine": {"type": "command", "command": "bash '"$SCRIPT_DIR"'/tmux-claude-status.sh"}'
fi

# --- Reload tmux ---
if [ -n "$TMUX" ]; then
  tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null && info "Reloaded tmux config" || warn "Failed to reload tmux, do it manually: tmux source-file ~/.config/tmux/tmux.conf"
else
  warn "Not inside tmux, reload manually: tmux source-file ~/.config/tmux/tmux.conf"
fi

echo ""
info "Installation complete!"
echo ""
echo "  Layout:"
echo "    Left:  ❐ session | dir git:(branch*)"
echo "    Right: Claude | ██░░░ 10% | ██░░░ 21% (3h 2m) | ██░░░ 16% (3d 4h) | [Opus]"
echo ""
echo "  Supports: Claude Code, Codex CLI, plain shell"
echo "  Auto-switches per tmux pane"
