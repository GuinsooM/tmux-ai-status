# tmux-ai-status

Real-time AI CLI status bar for tmux. Auto-detects and displays information for **Claude Code** and **Codex CLI**.

![layout](https://img.shields.io/badge/tmux-status_bar-blue)

## What it looks like

```
❐ 0 | myapp git:(main*)    Claude | █░░░░░░░░░ 10% | ██░░░░░░░░ 21% (3h 2m) | ██░░░░░░░░ 16% (3d 4h) | [Opus 4.6]
      ╰─ left: dir + git   ╰─ right: CLI + context bar + 5h quota + 7d quota + model
```

Switches automatically per tmux pane:
- **Claude Code** → context usage, 5h/7d rate limits, model name
- **Codex CLI** → context usage, 5h/7d rate limits, model name
- **Plain shell** → directory + git branch only

## Prerequisites

- [oh-my-tmux](https://github.com/gpakosz/.tmux)
- `jq`, `git`, `md5sum`
- Claude Code and/or Codex CLI
- [Claude HUD plugin](https://github.com/jarrodwatts/claude-hud) (for Claude 5h/7d usage data)

## Install

```bash
git clone https://github.com/GuinsooM/tmux-ai-status.git ~/.config/tmux/ai-status
bash ~/.config/tmux/ai-status/install.sh
```

## Uninstall

```bash
bash ~/.config/tmux/ai-status/uninstall.sh
```

## How it works

```
┌─────────────┐    stdin JSON     ┌───────────────────────┐    cache file     ┌─────────┐
│ Claude Code │ ─────────────────▶│ tmux-claude-status.sh │ ───────────────▶ │  tmux   │
└─────────────┘                   └───────────────────────┘   /tmp/claude-*   │ status  │
                                                                              │  bar    │
┌─────────────┐    session files  ┌───────────────────────┐                   │         │
│  Codex CLI  │ ─────────────────▶│ tmux-codex-status.sh  │ ────────────────▶│         │
└─────────────┘  ~/.codex/sessions└───────────────────────┘                   └─────────┘
                                          ▲
                                          │ dispatched by
                                  ┌───────────────────┐
                                  │ tmux-ai-status.sh │ ◀── #() in status-left/right
                                  └───────────────────┘
                                          ▲
                                          │ triggered on window switch
                                  ┌────────────────────────┐
                                  │ tmux-ai-status-hook.sh │ ◀── pane-focus-in hook
                                  └────────────────────────┘
```

### Per-pane isolation

Each Claude Code instance writes cache files keyed by workspace directory hash (`/tmp/claude-status-$USER-$HASH.tmux`). When you switch tmux windows, the hook triggers a refresh, and `tmux-ai-status.sh` reads the cache matching the active pane's `cwd`.

### Color scheme

| Element | Color | Condition |
|---------|-------|-----------|
| Context bar (empty) | Light green | < 50% |
| Context bar (empty) | Yellow | 50-80% |
| Context bar (empty) | Red | > 80% |
| 5h quota (empty) | Light blue | < 50% |
| 7d quota (empty) | Light pink | < 50% |
| Directory | Light green | — |
| Git branch | Red | — |
| Model name | Cyan | — |
| Separators | Grey | — |

## Files

| File | Purpose |
|------|---------|
| `tmux-ai-status.sh` | Main dispatcher - detects CLI type, routes to correct handler |
| `tmux-claude-status.sh` | Claude Code statusline callback - writes tmux cache |
| `tmux-codex-status.sh` | Parses Codex session files for usage data |
| `tmux-ai-status-hook.sh` | Forces tmux status refresh on window switch |
| `install.sh` | Patches oh-my-tmux config |
| `uninstall.sh` | Restores from backup |

## License

MIT
