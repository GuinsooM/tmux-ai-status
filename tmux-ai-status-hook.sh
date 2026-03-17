#!/bin/bash
# Called by tmux pane-focus-in hook to force status bar refresh.
# Briefly set interval to 1s, then schedule restore to 10s after 2 seconds.
tmux set -g status-interval 1
(sleep 2 && tmux set -g status-interval 10) &>/dev/null &
