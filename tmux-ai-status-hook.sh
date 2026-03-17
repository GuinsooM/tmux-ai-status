#!/bin/bash
# Called by tmux pane-focus-in hook to force status bar refresh.
# Clears the #() cache by toggling status-interval.
tmux set -g status-interval 1
sleep 0.1
tmux set -g status-interval 10
