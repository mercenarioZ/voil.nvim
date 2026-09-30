#!/usr/bin/env bash
# Build the fixtures for scripts/demo.lua, then run it in a throwaway tmux
# session and print what the terminal shows (ANSI escapes included).
#
#   bash scripts/capture.sh > /tmp/demo.ansi
#
# Needs: nvim, jj, git, tmux.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
session="voil-demo"
socket="voil-demo"

cleanup() {
  tmux -L "$socket" kill-server 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

repo="$work/demo"
mkdir -p "$repo/sub"
(cd "$repo" && jj git init --colocate >/dev/null 2>&1)
printf 'one\n' >"$repo/changed.txt"
printf 'two\n' >"$repo/old-name.txt"
printf 'three\n' >"$repo/untouched.txt"
printf 'four\n' >"$repo/sub/changed.txt"
printf 'five\n' >"$repo/sub/untouched.txt"
(cd "$repo" && jj commit -m init >/dev/null 2>&1)
printf 'one more\n' >>"$repo/changed.txt"
printf 'new\n' >"$repo/added.txt"
mv "$repo/old-name.txt" "$repo/renamed.txt"
printf 'four more\n' >>"$repo/sub/changed.txt"
rm "$repo/untouched.txt"
printf 'three again\n' >"$repo/untouched.txt"

cat >"$work/tmux.conf" <<'EOF'
set -g default-terminal "tmux-256color"
set -as terminal-features "*:RGB"
set -g status off
EOF

tmux -L "$socket" -f "$work/tmux.conf" new-session -d -s "$session" -x 76 -y 14
tmux -L "$socket" send-keys -t "$session" \
  "VOIL_ROOT='$root' DEMO_DIR='$repo' nvim -u '$root/scripts/demo.lua'" Enter

sleep 3
tmux -L "$socket" capture-pane -t "$session" -e -p
