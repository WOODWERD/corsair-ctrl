#!/bin/bash
# Edge Ctrl spike — Claude Code hook forwarder.
# Claude Code pipes one JSON event to stdin. We append it to a log (proof the
# hook fired, even with the panel closed) and POST it to the panel. Never blocks
# Claude: 1 s timeout, always exits 0.
LOG_DIR="$HOME/Library/Logs/EdgeCtrl"
mkdir -p "$LOG_DIR"
payload="$(cat)"
printf '%s\n' "$payload" >> "$LOG_DIR/hooks.jsonl"
curl -s -m 1 -X POST -H 'Content-Type: application/json' \
  --data-binary "$payload" http://127.0.0.1:47615/event >/dev/null 2>&1 || true
exit 0
