#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .claude-plugin/plugin.json ] || { echo "FAIL: manifest missing"; exit 1; }
python3 - <<'PY' 2>/dev/null || { echo "FAIL: manifest invalid"; exit 1; }
import json
with open(".claude-plugin/plugin.json") as f:
    d = json.load(f)
assert d.get("name") == "super-manus", f"name mismatch: {d.get('name')!r}"
assert isinstance(d.get("version"), str) and d["version"], "version missing/empty"
assert isinstance(d.get("description"), str) and d["description"], "description missing/empty"
assert isinstance(d.get("keywords"), list) and all(isinstance(k, str) for k in d["keywords"]), "keywords must be list[str]"
PY
echo OK
