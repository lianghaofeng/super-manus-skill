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

# Case A: super-manus not enabled (no docs/super-manus/prd/) → emits the
# "not enabled" reminder via emit_context with /super-manus:start guidance.
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: Case A — expected not-enabled reminder JSON, got invalid output"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart", d
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "not enabled" in ctx.lower(), f"missing not-enabled phrase: {ctx!r}"
assert "/super-manus:start" in ctx, f"must point at /super-manus:start: {ctx!r}"
PY

# === v0.4 cases — project-global PRD; no per-feature wrapper, no .super-manus/active ===

# Case V0.4-A: super-manus enabled but no impl/<module>/<update>/ yet
# → emits "no impl yet, run brainstorm/sync" message
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh >/dev/null
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: v0.4-A — empty-impl banner wrong"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "brainstorm" in ctx.lower() or "sync" in ctx.lower(), f"v0.4-A: must suggest /super-manus:brainstorm or /sync: {ctx[:300]!r}"
PY

# Case V0.4-B: project-global super-manus + active update under
# docs/super-manus/impl/<module>/<update>/ → injects task_plan.md from update + pointers
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-update.sh "api" "mvp" >/dev/null
TODAY=$(date +%F)
UPDATE="docs/super-manus/impl/api/${TODAY}-mvp"

bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" UPDATE="$UPDATE" python3 - <<'PY' || { echo "FAIL: v0.4-B — banner / paths wrong"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
update = os.environ["UPDATE"]
# Pointers to update's three files
assert f"{update}/findings.md" in ctx, f"v0.4-B: must point at update findings.md: {ctx[:400]!r}"
assert f"{update}/progress.md" in ctx, f"v0.4-B: must point at update progress.md"
# Project-global prd/_index.md content or pointer (the hook's prefix may be relative)
assert "prd/_index.md" in ctx or "docs/super-manus/prd/<module>.md" in ctx, f"v0.4-B: must inject/point at project-global prd content: {ctx[:400]!r}"
# task_plan.md content from update is referenced
assert "task_plan.md" in ctx, f"v0.4-B: must reference the update's task_plan.md"
PY

# Case V0.4-C: orphan / corrupt impl folder (e.g. update folder without task_plan.md) → no crash
rm -f "$UPDATE/task_plan.md"
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: v0.4-C — missing task_plan.md should not produce invalid JSON"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart", d
PY

echo OK
