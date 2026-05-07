#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .claude-plugin/plugin.json ] || { echo "FAIL: manifest missing"; exit 1; }
[ -f .claude-plugin/marketplace.json ] || { echo "FAIL: marketplace.json missing"; exit 1; }
python3 - <<'PY' || { echo "FAIL: manifest validation failed"; exit 1; }
import json, sys

with open(".claude-plugin/plugin.json") as f:
    d = json.load(f)
assert d.get("name") == "super-manus", f"plugin.json name mismatch: {d.get('name')!r}"
assert isinstance(d.get("version"), str) and d["version"], "plugin.json version missing/empty"
assert isinstance(d.get("description"), str) and d["description"], "plugin.json description missing/empty"
assert isinstance(d.get("keywords"), list) and all(isinstance(k, str) for k in d["keywords"]), "plugin.json keywords must be list[str]"

# marketplace.json's plugins[0] must stay in sync with plugin.json — otherwise
# users browsing /plugin marketplace see the wrong version. The two files were
# silently divergent before v0.7 (marketplace stuck at 0.1.0 through six bumps).
with open(".claude-plugin/marketplace.json") as f:
    m = json.load(f)
plugins = m.get("plugins")
assert isinstance(plugins, list) and len(plugins) >= 1, "marketplace.json must list at least one plugin"
sm = next((p for p in plugins if p.get("name") == "super-manus"), None)
assert sm is not None, "marketplace.json must include a plugin entry named 'super-manus'"
assert sm.get("version") == d["version"], (
    f"marketplace.json plugins[super-manus].version ({sm.get('version')!r}) "
    f"must match plugin.json version ({d['version']!r})"
)
assert sm.get("description") == d["description"], (
    f"marketplace.json plugins[super-manus].description must match plugin.json description"
)
assert sm.get("keywords") == d["keywords"], (
    f"marketplace.json plugins[super-manus].keywords must match plugin.json keywords"
)
PY
echo OK
