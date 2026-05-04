#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f hooks/hooks.json ] || { echo "FAIL: hooks/hooks.json missing"; exit 1; }

python3 - <<'PY' 2>/dev/null || { echo "FAIL: hooks.json invalid"; exit 1; }
import json
with open("hooks/hooks.json") as f:
    d = json.load(f)
hooks = d.get("hooks", {})
# All three event keys must be present
for evt in ("SessionStart", "Stop", "PostToolUse"):
    assert evt in hooks, f"missing event: {evt}"
    assert isinstance(hooks[evt], list) and len(hooks[evt]) >= 1, f"{evt} must be a non-empty list"

# SessionStart matcher must include the three trigger types we care about
ss = hooks["SessionStart"][0]
matcher = ss.get("matcher", "")
for kw in ("startup", "clear", "compact"):
    assert kw in matcher, f"SessionStart matcher missing keyword '{kw}': {matcher!r}"

# SessionStart entry should preserve async: false (blocks session until reminder injected)
ss_hooks = ss.get("hooks", [])
assert ss_hooks, "SessionStart hooks list empty"
assert ss_hooks[0].get("async") is False, f"SessionStart hook should set async=false, got: {ss_hooks[0].get('async')!r}"

# PostToolUse matcher must be exactly "Bash"
pt = hooks["PostToolUse"][0]
assert pt.get("matcher") == "Bash", f"PostToolUse matcher must be 'Bash', got: {pt.get('matcher')!r}"

# Every hook command must reference run-hook.cmd via CLAUDE_PLUGIN_ROOT
for evt, entries in hooks.items():
    for entry in entries:
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            assert "CLAUDE_PLUGIN_ROOT" in cmd, f"{evt} command must use ${{CLAUDE_PLUGIN_ROOT}}: {cmd}"
            assert "run-hook.cmd" in cmd, f"{evt} command must invoke run-hook.cmd: {cmd}"
            assert h.get("type") == "command", f"{evt} hook type must be 'command'"
PY

# All three stub scripts exist, are executable, and emit valid JSON
for s in session-start.sh session-end.sh post-commit.sh; do
  [ -x "hooks/$s" ] || { echo "FAIL: hooks/$s missing or not executable"; exit 1; }
  out=$(bash "hooks/$s" </dev/null)
  echo "$out" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null \
    || { echo "FAIL: hooks/$s did not emit valid JSON, got: $out"; exit 1; }
done

echo OK
