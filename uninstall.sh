#!/bin/bash
# uninstall.sh - Remove tmux-ai-status from oh-my-tmux configuration
#
# Restores tmux.conf.local from the most recent backup created by install.sh

set -e

TMUX_LOCAL="${HOME}/.config/tmux/tmux.conf.local"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Find most recent backup
backup=$(ls -t "${TMUX_LOCAL}.bak."* 2>/dev/null | head -1)
[ -n "$backup" ] || error "No backup found. Manually remove ai-status references from $TMUX_LOCAL"

cp "$backup" "$TMUX_LOCAL"
info "Restored from $backup"

# Remove Claude Code statusline config
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && grep -q 'tmux-claude-status.sh' "$CLAUDE_SETTINGS"; then
  tmp=$(mktemp)
  jq 'del(.statusLine)' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
  info "Removed Claude Code statusline config"
fi

# Clean up cache files
rm -f /tmp/claude-status-${USER}*.tmux /tmp/claude-cwd-${USER}*.txt /tmp/codex-status-${USER}.tmux
info "Cleaned up cache files"

if [ -n "$TMUX" ]; then
  tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null && info "Reloaded tmux config"
fi

info "Uninstall complete"
