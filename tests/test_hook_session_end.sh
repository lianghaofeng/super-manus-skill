#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up an isolated project with hooks + an active feature
cp -r hooks "$TMP/"
cp -r scripts "$TMP/"
cp -r templates "$TMP/"
cd "$TMP"

# Helper: assert hook output equals literal "{}"
assert_noop() {
  local out="$1" label="$2"
  if [ "$out" != "{}" ]; then
    echo "FAIL: $label — expected {} no-op, got: $out"
    exit 1
  fi
}

# Helper: assert hook output is a Stop reminder mentioning Session log + Completed commits
assert_reminder() {
  local out="$1" label="$2"
  printf '%s' "$out" > "$TMP/out.json"
  HOOK_OUT_FILE="$TMP/out.json" LABEL="$label" python3 - <<'PY' || { echo "FAIL: $label — output is not a valid Stop reminder JSON"; exit 1; }
import json, os, sys
label = os.environ["LABEL"]
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d["hookSpecificOutput"]["hookEventName"] == "Stop", f"{label}: wrong event"
ctx = d["hookSpecificOutput"]["additionalContext"]
assert "Session log" in ctx, f"{label}: missing Session log ref: {ctx[:200]!r}"
assert "Completed commits" in ctx, f"{label}: missing Completed commits ref"
assert "re-read" in ctx.lower(), f"{label}: must explicitly tell agent to re-read progress.md (design §11 risk mitigation)"
assert "task_plan.md" in ctx, f"{label}: should reference task_plan.md for blocked-phase update"
PY
}

# Case A: no active feature → no-op
out=$(bash hooks/session-end.sh)
assert_noop "$out" "Case A (no active feature)"

# Case B: active feature exists with progress.md → emits Stop reminder
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null
out=$(bash hooks/session-end.sh)
assert_reminder "$out" "Case B (active feature with progress.md)"

# Case C: active file points to ghost folder → no-op
echo "2026-05-04-ghost" > .super-manus/active
out=$(bash hooks/session-end.sh)
assert_noop "$out" "Case C (ghost folder)"

# Case D: active feature exists but progress.md missing → no-op
TODAY=$(date +%F)
echo "${TODAY}-demo" > .super-manus/active
rm "docs/super-manus/${TODAY}-demo/progress.md"
out=$(bash hooks/session-end.sh)
assert_noop "$out" "Case D (missing progress.md)"

echo OK
