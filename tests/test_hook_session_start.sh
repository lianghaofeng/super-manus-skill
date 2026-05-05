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

# Case B: active v0.1 feature exists with task_plan.md → injects full plan + paths to other files
# Scaffold v0.1 layout directly (sm-start now creates v0.2; commit 4 will teach this hook
# to also handle v0.2-shaped features). The v0.1 path here verifies legacy compatibility.
mkdir -p .super-manus
TODAY=$(date +%F)
V01_FOLDER="docs/super-manus/${TODAY}-demo"
mkdir -p "$V01_FOLDER"
for f in task_plan.md prd.md findings.md progress.md; do
  sed "s|<feature title>|demo|g" "templates/$f" > "$V01_FOLDER/$f"
done
echo "${TODAY}-demo" > .super-manus/active

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

# === v0.2 cases ===
rm -rf "docs/super-manus/${TODAY}-demo"

# Case V0.2-A: v0.2 feature with active update → emits banner + injects task_plan.md from the update,
# pointers to update's findings.md / progress.md, and to feature-level prd/_index.md.
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "v02demo" >/dev/null
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-update.sh "api" "mvp" >/dev/null
V02_FEATURE="docs/super-manus/${TODAY}-v02demo"
V02_UPDATE="$V02_FEATURE/impl/api/${TODAY}-mvp"
echo "${TODAY}-v02demo" > .super-manus/active

bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" V02_FEATURE="$V02_FEATURE" V02_UPDATE="$V02_UPDATE" python3 - <<'PY' || { echo "FAIL: v0.2-A — banner / paths wrong"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
feature = os.environ["V02_FEATURE"]
update = os.environ["V02_UPDATE"]
# Banner
assert "v0.2" in ctx, f"v0.2-A: banner must mention v0.2, got: {ctx[:300]!r}"
assert feature in ctx, f"v0.2-A: must mention feature folder"
assert "api/" in ctx, f"v0.2-A: must reference active update path (e.g. api/<date>-mvp)"
# Pointers to update's three files + feature-level prd/_index.md
assert f"{update}/findings.md" in ctx, f"v0.2-A: must point at update findings.md"
assert f"{update}/progress.md" in ctx, f"v0.2-A: must point at update progress.md"
assert f"{feature}/prd/_index.md" in ctx, f"v0.2-A: must point at feature-level prd/_index.md"
# task_plan.md content from update is injected
assert "Task Plan:" in ctx, f"v0.2-A: must inject the update's task_plan.md content"
PY

# Case V0.2-B: v0.2 feature with NO impl/<m>/<u>/ yet → emit "no impl yet, run brainstorm/sync" message
EMPTY_NAME="${TODAY}-empty-v02"
EMPTY_FEATURE="docs/super-manus/$EMPTY_NAME"
mkdir -p "$EMPTY_FEATURE/prd" "$EMPTY_FEATURE/impl"
echo "$EMPTY_NAME" > .super-manus/active
bash hooks/session-start.sh > "$OUT_FILE"
HOOK_OUT_FILE="$OUT_FILE" python3 - <<'PY' || { echo "FAIL: v0.2-B — empty v0.2 feature banner wrong"; exit 1; }
import json, os
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "v0.2" in ctx, f"v0.2-B: must mention v0.2"
assert "brainstorm" in ctx.lower() or "sync" in ctx.lower(), f"v0.2-B: must suggest /super-manus:brainstorm or /sync"
PY

echo OK
