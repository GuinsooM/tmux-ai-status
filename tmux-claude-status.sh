#!/bin/bash
# Called by Claude Code's statusline. Writes tmux-formatted info to cache file.
# Outputs nothing to Claude Code (display is in tmux).

USAGE_CACHE="$HOME/.claude/plugins/claude-hud/.usage-cache.json"
input=$(cat)

# Cache file keyed by workspace directory
cwd_raw=$(echo "$input" | jq -r '.workspace.current_dir // empty')
if [ -n "$cwd_raw" ]; then
  cwd_hash=$(echo -n "$cwd_raw" | md5sum | cut -c1-8)
else
  cwd_hash="default"
fi
CACHE_FILE="/tmp/claude-status-${USER}-${cwd_hash}.tmux"
CACHE_LEFT="/tmp/claude-status-left-${USER}-${cwd_hash}.tmux"
CACHE_USAGE="/tmp/claude-status-usage-${USER}.tmux"
# Also write a "latest" pointer so tmux-ai-status can find caches by cwd
echo "$cwd_raw" > "/tmp/claude-cwd-${USER}-${cwd_hash}.txt"

# --- Pass through to Claude HUD (keeps usage-cache.json fresh) ---
plugin_dir=$(ls -d "$HOME"/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null \
  | awk -F/ '{ print $(NF-1) "\t" $0 }' \
  | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
  | tail -1 | cut -f2-)
if [ -n "$plugin_dir" ] && [ -x "$HOME/.bun/bin/bun" ]; then
  echo "$input" | "$HOME/.bun/bin/bun" "${plugin_dir}src/index.ts" > /dev/null 2>&1
fi
# Output nothing to Claude Code (display is in tmux)
echo ""

# --- Helper: generate a tmux progress bar ---
make_bar() {
  local pct=${1:-0} width=${2:-10} fg_color="$3" dim_color="${4:-colour245}"
  local filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local bar="" empty_bar="" i
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty); do empty_bar="${empty_bar}░"; done
  echo "#[fg=${fg_color}]${bar}#[fg=${dim_color}]${empty_bar}#[default]"
}

# --- Generate tmux cache (background) ---
{
  cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
  model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
  # Shorten long model display names
  case "$model" in
    *Opus*4.6*1M*)   model="opus-4.6-1M" ;;
    *Opus*4.6*)      model="opus-4.6" ;;
    *Opus*4.5*)      model="opus-4.5" ;;
    *Sonnet*4.6*)    model="sonnet-4.6" ;;
    *Sonnet*4.5*)    model="sonnet-4.5" ;;
    *Haiku*4.5*)     model="haiku-4.5" ;;
  esac
  ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

  # Usage from HUD cache (prefer .data, fall back to .lastGoodData seamlessly)
  u5_pct="" u7_pct="" u5_reset_at="" u7_reset_at=""
  if [ -f "$USAGE_CACHE" ]; then
    u5_pct=$(jq -r '(.data.fiveHour // .lastGoodData.fiveHour) // empty' "$USAGE_CACHE" 2>/dev/null)
    u7_pct=$(jq -r '(.data.sevenDay // .lastGoodData.sevenDay) // empty' "$USAGE_CACHE" 2>/dev/null)
    u5_reset_at=$(jq -r '(.data.fiveHourResetAt // .lastGoodData.fiveHourResetAt) // empty' "$USAGE_CACHE" 2>/dev/null)
    u7_reset_at=$(jq -r '(.data.sevenDayResetAt // .lastGoodData.sevenDayResetAt) // empty' "$USAGE_CACHE" 2>/dev/null)
  fi

  parts=""

  # --- Write dir+git info to separate cache for status-left ---
  # Compact format: "dir branch*" — pad_to in tmux-ai-status.sh handles fixed width
  left_parts=""
  if [ -n "$cwd" ]; then
    dir_name=$(basename "$cwd")
    left_parts=" #[fg=colour114]${dir_name}#[default]"
  fi
  if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
      dirty=""
      if ! git -C "$cwd" diff --quiet --no-optional-locks 2>/dev/null || ! git -C "$cwd" diff --cached --quiet --no-optional-locks 2>/dev/null; then
        dirty="*"
      fi
      left_parts="${left_parts} #[fg=red]${branch}${dirty}#[default]"
    fi
  fi
  echo "$left_parts" > "$CACHE_LEFT"

  # --- Render shared usage cache (all tabs see the same latest data) ---
  usage_parts=""
  if [ -n "$u5_pct" ]; then
    if [ "$u5_pct" -ge 80 ] 2>/dev/null; then
      u5_color="red"
    elif [ "$u5_pct" -ge 50 ] 2>/dev/null; then
      u5_color="yellow"
    else
      u5_color="colour33"
    fi
    u5_bar=$(make_bar "$u5_pct" 10 "$u5_color" "colour117")
    u5_label=$(printf '%3d%%' "$u5_pct")
    u5_reset="        "
    if [ -n "$u5_reset_at" ]; then
      now=$(date +%s)
      reset_epoch=$(date -d "$u5_reset_at" +%s 2>/dev/null)
      if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now" ] 2>/dev/null; then
        diff_min=$(( (reset_epoch - now) / 60 ))
        hours=$((diff_min / 60)); mins=$((diff_min % 60))
        u5_reset=$(printf '(%dh%02dm)' "$hours" "$mins")
        u5_reset=$(printf '%-8s' "$u5_reset")
      fi
    fi
    u5_str="${u5_bar} #[fg=${u5_color}]${u5_label} ${u5_reset}#[default]"
    usage_parts="${usage_parts} #[fg=colour245]|#[default] ${u5_str}"
  fi
  if [ -n "$u7_pct" ]; then
    if [ "$u7_pct" -ge 80 ] 2>/dev/null; then
      u7_color="red"
    elif [ "$u7_pct" -ge 50 ] 2>/dev/null; then
      u7_color="yellow"
    else
      u7_color="magenta"
    fi
    u7_bar=$(make_bar "$u7_pct" 10 "$u7_color" "colour218")
    u7_label=$(printf '%3d%%' "$u7_pct")
    u7_reset="        "
    if [ -n "$u7_reset_at" ]; then
      now=$(date +%s)
      reset_epoch=$(date -d "$u7_reset_at" +%s 2>/dev/null)
      if [ -n "$reset_epoch" ] && [ "$reset_epoch" -gt "$now" ] 2>/dev/null; then
        diff_hrs=$(( (reset_epoch - now) / 3600 ))
        days=$((diff_hrs / 24)); hours=$((diff_hrs % 24))
        u7_reset=$(printf '(%dd%02dh)' "$days" "$hours")
        u7_reset=$(printf '%-8s' "$u7_reset")
      fi
    fi
    u7_str="${u7_bar} #[fg=${u7_color}]${u7_label} ${u7_reset}#[default]"
    usage_parts="${usage_parts} #[fg=colour245]|#[default] ${u7_str}"
  fi
  echo "$usage_parts" > "$CACHE_USAGE"

  # --- Per-tab cache: CLI label + context bar (session-specific) ---
  parts="#[fg=colour203,bold]Claude#[default] #[fg=colour245]|#[default]"

  if [ "$ctx_pct" -ge 80 ] 2>/dev/null; then
    ctx_color="red"
  elif [ "$ctx_pct" -ge 50 ] 2>/dev/null; then
    ctx_color="yellow"
  else
    ctx_color="green"
  fi
  ctx_bar=$(make_bar "$ctx_pct" 10 "$ctx_color" "colour114")
  ctx_label=$(printf '%3d%%' "$ctx_pct")
  parts="${parts} ${ctx_bar} #[fg=${ctx_color}]${ctx_label}#[default]"

  echo "$parts" > "$CACHE_FILE"

  # --- Per-tab model suffix cache (fixed width) ---
  model_label=$(printf '%-12s' "$model")
  echo " #[fg=colour245]|#[default] #[fg=cyan][${model_label}]#[default]" > "${CACHE_FILE%.tmux}-model.tmux"
} &
