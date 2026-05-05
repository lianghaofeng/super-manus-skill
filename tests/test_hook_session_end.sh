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

# Helper: assert hook output is a Stop reminder mentioning Session log + Completed commits.
# Stop hooks must emit {"decision":"block","reason":...} so the agent actually receives
# the reminder; systemMessage / additionalContext both fail to reach the model on Stop.
assert_reminder() {
  local out="$1" label="$2"
  printf '%s' "$out" > "$TMP/out.json"
  HOOK_OUT_FILE="$TMP/out.json" LABEL="$label" python3 - <<'PY' || { echo "FAIL: $label — output is not a valid Stop reminder JSON"; exit 1; }
import json, os, sys
label = os.environ["LABEL"]
with open(os.environ["HOOK_OUT_FILE"]) as f:
    d = json.load(f)
assert d.get("decision") == "block", f"{label}: Stop hook must emit decision=block, got: {d}"
assert "reason" in d, f"{label}: missing reason field"
assert "systemMessage" not in d, f"{label}: must not fall back to systemMessage (model wouldn't see it)"
assert "hookSpecificOutput" not in d, f"{label}: must not use hookSpecificOutput (invalid for Stop)"
ctx = d["reason"]
assert "Session log" in ctx, f"{label}: missing Session log ref: {ctx[:200]!r}"
assert "Completed commits" in ctx, f"{label}: missing Completed commits ref"
assert "re-read" in ctx.lower(), f"{label}: must explicitly tell agent to re-read progress.md (design §11 risk mitigation)"
assert "task_plan.md" in ctx, f"{label}: should reference task_plan.md for blocked-phase update"
PY
}

# Case A: no active feature → no-op (regardless of stdin)
out=$(bash hooks/session-end.sh </dev/null)
assert_noop "$out" "Case A (no active feature)"

# Case B: active feature exists with progress.md → emits Stop reminder
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null
TODAY=$(date +%F)
FOLDER="docs/super-manus/${TODAY}-demo"
out=$(bash hooks/session-end.sh </dev/null)
assert_reminder "$out" "Case B (active feature with progress.md, empty stdin)"

# Case B2: same feature but Claude Code passes a payload without stop_hook_active → still emits
# (use a fresh sentinel state — remove any leftover from prior cases)
rm -f "$FOLDER/.session-logged"
out=$(printf '{"session_id":"abc"}' | bash hooks/session-end.sh)
assert_reminder "$out" "Case B2 (payload without stop_hook_active flag)"

# Case B3: stop_hook_active=true (re-stop after block) → no-op AND records session_id as logged
rm -f "$FOLDER/.session-logged"
out=$(printf '{"stop_hook_active": true, "session_id": "abc"}' | bash hooks/session-end.sh)
assert_noop "$out" "Case B3 (stop_hook_active=true → break the block loop)"
[ -f "$FOLDER/.session-logged" ] || { echo "FAIL: Case B3 should have written sentinel"; exit 1; }
[ "$(cat "$FOLDER/.session-logged")" = "abc" ] || { echo "FAIL: Case B3 sentinel content wrong: $(cat "$FOLDER/.session-logged")"; exit 1; }

# Case B4: subsequent turn within same session (sentinel matches session_id) → no-op,
# do NOT pester the agent on every reply
out=$(printf '{"session_id":"abc"}' | bash hooks/session-end.sh)
assert_noop "$out" "Case B4 (already logged this session → no-op for the rest of the session)"

# Case B5: NEW session (different session_id) → block again (one log per session)
out=$(printf '{"session_id":"different-session"}' | bash hooks/session-end.sh)
assert_reminder "$out" "Case B5 (new session_id → block again, one log per session)"

# Case C: active file points to ghost folder → no-op
echo "2026-05-04-ghost" > .super-manus/active
out=$(bash hooks/session-end.sh </dev/null)
assert_noop "$out" "Case C (ghost folder)"

# Case D: active feature exists but progress.md missing → no-op
TODAY=$(date +%F)
echo "${TODAY}-demo" > .super-manus/active
rm "docs/super-manus/${TODAY}-demo/progress.md"
out=$(bash hooks/session-end.sh </dev/null)
assert_noop "$out" "Case D (missing progress.md)"

echo OK
