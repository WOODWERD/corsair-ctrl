#!/bin/bash
# Edge Ctrl spike — add (or remove) the Edge Ctrl hooks in ~/.claude/settings.json.
#   bash install-hooks.sh            install
#   bash install-hooks.sh remove     remove
# Backs up settings.json first. Leaves every other hook untouched.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK_CMD="bash \"$HERE/edge-hook.sh\""
SETTINGS="$HOME/.claude/settings.json"
MODE="${1:-install}"

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-edgectrl-$(date +%Y%m%d-%H%M%S)"

/usr/bin/python3 - "$SETTINGS" "$HOOK_CMD" "$MODE" <<'PY'
import json, sys
path, cmd, mode = sys.argv[1:4]
with open(path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})
events = {"SessionStart": None, "UserPromptSubmit": None, "PreToolUse": "*",
          "Notification": None, "Stop": None, "SessionEnd": None}
for ev, matcher in events.items():
    groups = [g for g in hooks.get(ev, [])
              if not any(h.get("command") == cmd for h in g.get("hooks", []))]
    if mode == "install":
        g = {"hooks": [{"type": "command", "command": cmd, "timeout": 5}]}
        if matcher:
            g["matcher"] = matcher
        groups.append(g)
    if groups:
        hooks[ev] = groups
    else:
        hooks.pop(ev, None)
if not hooks:
    s.pop("hooks")
with open(path, "w") as f:
    json.dump(s, f, indent=2)
    f.write("\n")
print(("Installed" if mode == "install" else "Removed"), "Edge Ctrl hooks in", path)
PY
