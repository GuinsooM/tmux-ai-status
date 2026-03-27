#!/bin/bash
# Extract Codex usage data from session files and write tmux-formatted cache.
# Called periodically by tmux-ai-status.sh when Codex is detected.

CACHE_FILE="/tmp/codex-status-${USER}.tmux"
SESSIONS_DIR="$HOME/.codex/sessions"
PANE_CWD=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)

find_active_rollout() {
  local pane_pid codex_pid="" cpid gpid target
  pane_pid=$(tmux display-message -p '#{pane_pid}' 2>/dev/null)
  [ -n "$pane_pid" ] || return 0

  for cpid in $(ps --ppid "$pane_pid" -o pid= 2>/dev/null); do
    if ps -p "$cpid" -o comm= 2>/dev/null | grep -qi '^codex$'; then
      codex_pid="$cpid"
      break
    fi
    for gpid in $(ps --ppid "$cpid" -o pid= 2>/dev/null); do
      if ps -p "$gpid" -o comm= 2>/dev/null | grep -qi '^codex$'; then
        codex_pid="$gpid"
        break 2
      fi
    done
  done

  [ -n "$codex_pid" ] || return 0
  for fd in /proc/"$codex_pid"/fd/*; do
    target=$(readlink -f "$fd" 2>/dev/null) || continue
    case "$target" in
      "$SESSIONS_DIR"/*/rollout-*.jsonl)
        echo "$target"
        return 0
        ;;
    esac
  done
}

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

center_text() {
  local width="$1" text="$2"
  local len=${#text}
  if [ "$len" -ge "$width" ]; then
    printf '%s' "$text"
    return
  fi

  local total_pad=$(( width - len ))
  local left_pad=$(( total_pad / 2 ))
  local right_pad=$(( total_pad - left_pad ))
  printf '%*s%s%*s' "$left_pad" "" "$text" "$right_pad" ""
}

format_effort_tag() {
  local effort
  effort=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$effort" in
    low) printf '(L)' ;;
    medium|med) printf '(M)' ;;
    high) printf '(H)' ;;
    xhigh|max|ultra|ultrathink) printf '(X)' ;;
    *) printf '' ;;
  esac
}

ACTIVE_ROLLOUT=$(find_active_rollout)

# Prefer the rollout file that the active Codex process is currently writing.
# Fall back to matching by pane cwd, then to the newest rollout overall. Rate
# limits remain global, so we still grab the newest token_count event that
# includes them across recent rollouts if needed.
selection_json=$(python - "$SESSIONS_DIR" "$PANE_CWD" "$ACTIVE_ROLLOUT" <<'PY'
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

sessions_dir = Path(sys.argv[1])
pane_cwd = sys.argv[2] if len(sys.argv) > 2 else ""
active_rollout = Path(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else None

def parse_rollout(path):
    latest_token = None
    latest_with_limits = None
    latest_cwd = ""
    latest_effort = ""
    try:
        with path.open() as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("type") == "turn_context":
                    payload = obj.get("payload", {})
                    latest_cwd = payload.get("cwd") or latest_cwd
                    latest_effort = (
                        payload.get("effort")
                        or payload.get("collaboration_mode", {}).get("settings", {}).get("reasoning_effort")
                        or latest_effort
                    )
                elif obj.get("type") == "event_msg" and obj.get("payload", {}).get("type") == "token_count":
                    latest_token = obj
                    if obj.get("payload", {}).get("rate_limits") is not None:
                        latest_with_limits = obj
    except Exception:
        return None, None, "", ""
    return latest_token, latest_with_limits, latest_cwd, latest_effort

files = []
today = datetime.now()
for days_ago in range(7):
    day_dir = sessions_dir / (today - timedelta(days=days_ago)).strftime("%Y/%m/%d")
    if day_dir.is_dir():
        files.extend(p for p in day_dir.glob("rollout-*.jsonl") if p.is_file())
files.sort(key=lambda p: p.stat().st_mtime, reverse=True)

selected_latest = None
selected_effort = None
global_latest = None
global_effort = None
global_latest_with_limits = None

if active_rollout and active_rollout.is_file():
    latest_token, latest_with_limits, _, latest_effort = parse_rollout(active_rollout)
    selected_latest = latest_token
    selected_effort = latest_effort
    global_latest_with_limits = latest_with_limits

for path in files:
    latest_token, latest_with_limits, latest_cwd, latest_effort = parse_rollout(path)

    if latest_token and global_latest is None:
        global_latest = latest_token
        global_effort = latest_effort
    if latest_with_limits and global_latest_with_limits is None:
        global_latest_with_limits = latest_with_limits
    if not selected_latest and pane_cwd and latest_token and latest_cwd == pane_cwd:
        selected_latest = latest_token
        selected_effort = latest_effort

    if selected_latest and global_latest_with_limits:
        break

result = {
    "latest": selected_latest or global_latest,
    "latest_with_limits": global_latest_with_limits or selected_latest or global_latest,
    "effort": selected_effort or global_effort,
}
if result["latest"] is not None:
    print(json.dumps(result, separators=(",", ":")))
PY
)

latest=$(echo "$selection_json" | jq -c '.latest // empty' 2>/dev/null)
latest_with_limits=$(echo "$selection_json" | jq -c '.latest_with_limits // empty' 2>/dev/null)
effort=$(echo "$selection_json" | jq -r '.effort // empty' 2>/dev/null)

if [ -z "$latest" ]; then
  echo "#[fg=colour84,bold]Codex #[default]#[fg=colour245](no data)#[default]" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

# Parse context from latest token_count
ctx_window=$(echo "$latest" | jq -r '.payload.info.model_context_window // 0')

# Parse rate_limits from the latest event that has them
rl_source="${latest_with_limits:-$latest}"
u5_pct=$(echo "$rl_source" | jq -r '.payload.rate_limits.primary.used_percent // empty')
u5_resets=$(echo "$rl_source" | jq -r '.payload.rate_limits.primary.resets_at // empty')
u7_pct=$(echo "$rl_source" | jq -r '.payload.rate_limits.secondary.used_percent // empty')
u7_resets=$(echo "$rl_source" | jq -r '.payload.rate_limits.secondary.resets_at // empty')

# Approximate Codex's context-used from the latest request size. `input_tokens`
# already includes the cached prompt portion, and `total_tokens` additionally
# accounts for the latest model output now present in the conversation state.
ctx_tokens=$(echo "$latest" | jq -r '.payload.info.last_token_usage.total_tokens // 0')
ctx_pct=0
if [ "$ctx_window" -gt 0 ] 2>/dev/null && [ "$ctx_tokens" -gt 0 ] 2>/dev/null; then
  ctx_pct=$(( ctx_tokens * 100 / ctx_window ))
  [ "$ctx_pct" -gt 100 ] && ctx_pct=100
fi

parts="#[fg=colour84,bold]Codex #[default]#[fg=colour245]|#[default]"

# Context bar
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

# 5-hour usage
if [ -n "$u5_pct" ]; then
  u5_int=${u5_pct%.*}
  if [ "$u5_int" -ge 80 ] 2>/dev/null; then
    u5_color="red"
  elif [ "$u5_int" -ge 50 ] 2>/dev/null; then
    u5_color="yellow"
  else
    u5_color="colour33"
  fi
  u5_bar=$(make_bar "$u5_int" 10 "$u5_color" "colour117")
  u5_label=$(printf '%3d%%' "$u5_int")
  u5_reset="        "
  if [ -n "$u5_resets" ]; then
    now=$(date +%s)
    if [ "$u5_resets" -gt "$now" ] 2>/dev/null; then
      diff_min=$(( (u5_resets - now) / 60 ))
      hours=$((diff_min / 60)); mins=$((diff_min % 60))
      u5_reset=$(printf '(%dh%02dm)' "$hours" "$mins")
      u5_reset=$(printf '%-8s' "$u5_reset")
    fi
  fi
  u5_str="${u5_bar} #[fg=${u5_color}]${u5_label} ${u5_reset}#[default]"
  parts="${parts} #[fg=colour245]|#[default] ${u5_str}"
fi

# 7-day usage
if [ -n "$u7_pct" ]; then
  u7_int=${u7_pct%.*}
  if [ "$u7_int" -ge 80 ] 2>/dev/null; then
    u7_color="red"
  elif [ "$u7_int" -ge 50 ] 2>/dev/null; then
    u7_color="yellow"
  else
    u7_color="magenta"
  fi
  u7_bar=$(make_bar "$u7_int" 10 "$u7_color" "colour218")
  u7_label=$(printf '%3d%%' "$u7_int")
  u7_reset="        "
  if [ -n "$u7_resets" ]; then
    now=$(date +%s)
    if [ "$u7_resets" -gt "$now" ] 2>/dev/null; then
      diff_sec=$(( u7_resets - now ))
      if [ "$diff_sec" -lt 86400 ]; then
        diff_min=$(( diff_sec / 60 ))
        hours=$((diff_min / 60)); mins=$((diff_min % 60))
        u7_reset=$(printf '(%dh%02dm)' "$hours" "$mins")
      else
        diff_hrs=$(( diff_sec / 3600 ))
        days=$((diff_hrs / 24)); hours=$((diff_hrs % 24))
        u7_reset=$(printf '(%dd%02dh)' "$days" "$hours")
      fi
      u7_reset=$(printf '%-8s' "$u7_reset")
    fi
  fi
  u7_str="${u7_bar} #[fg=${u7_color}]${u7_label} ${u7_reset}#[default]"
  parts="${parts} #[fg=colour245]|#[default] ${u7_str}"
fi

# Model
codex_model=$(grep '^model ' ~/.codex/config.toml 2>/dev/null | head -1 | sed 's/.*= *"\(.*\)"/\1/')
[ -z "$codex_model" ] && codex_model="?"
effort_tag=$(format_effort_tag "$effort")
[ -n "$effort_tag" ] && codex_model="${codex_model}${effort_tag}"
model_label=$(center_text 12 "$codex_model")
parts="${parts} #[fg=colour245]|#[default] #[fg=cyan][${model_label}]#[default]"

echo "$parts" > "$CACHE_FILE"
cat "$CACHE_FILE"
