#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Copy the hook system + templates into the temp project so the script's relative paths work
cp -r hooks "$TMP/"
cp -r scripts "$TMP/"
cp -r templates "$TMP/"
cd "$TMP"

OUT_FILE="$TMP/out.json"

# Case A: no .super-manus/active → emits the "no active feature" reminder via emit_context
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: Case A — expected no-active-feature reminder JSON, got invalid output"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart", d
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "no active super-manus feature" in ctx.lower(), f"missing no-active phrase: {ctx!r}"
PY

# Case B: active feature exists with task_plan.md → injects full plan + paths to other files
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null
# sm-start created docs/super-manus/<today>-demo/ with templates substituted, and wrote .super-manus/active

bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: Case B — hook output is not valid SessionStart JSON"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart", d
ctx = d["hookSpecificOutput"]["additionalContext"]
# Must contain the substituted title from task_plan.md
assert "# Task Plan: demo" in ctx, f"plan title missing: {ctx[:200]!r}"
# Must reference the sibling files
assert "findings.md" in ctx, f"findings.md ref missing: {ctx[:200]!r}"
assert "progress.md" in ctx, f"progress.md ref missing: {ctx[:200]!r}"
# Must reference the active folder path
assert "docs/super-manus/" in ctx, f"folder path missing: {ctx[:200]!r}"
PY

# Case C: active file points to a folder that doesn't exist on disk → falls back to no-active-feature reminder
echo "2026-05-04-ghost" > .super-manus/active
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: Case C — ghost folder should fall back to no-active reminder"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "no active super-manus feature" in ctx.lower(), f"ghost folder should fall back, got: {ctx[:200]!r}"
PY

# Case D: active file present but task_plan.md missing inside the folder → also falls back
TODAY=$(date +%F)
echo "${TODAY}-demo" > .super-manus/active
rm "docs/super-manus/${TODAY}-demo/task_plan.md"
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: Case D — missing task_plan.md should fall back to no-active reminder"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "no active super-manus feature" in ctx.lower(), f"missing task_plan should fall back, got: {ctx[:200]!r}"
PY

echo OK
