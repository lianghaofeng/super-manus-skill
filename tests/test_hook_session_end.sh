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

# Case B setup: active feature with progress.md
mkdir -p .super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh "demo" >/dev/null
TODAY=$(date +%F)
FOLDER="docs/super-manus/${TODAY}-demo"

# Case B: with default threshold (10), the first 9 turns are no-op; turn 10 blocks.
rm -f "$FOLDER/.session-state"
for i in 1 2 3 4 5 6 7 8 9; do
  out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
  assert_noop "$out" "Case B (turn $i, below default threshold 10)"
done
out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
assert_reminder "$out" "Case B (turn 10 hits threshold, blocks)"

# Case B2: stop_hook_active=true (agent done writing) → no-op AND counter reset to 0
out=$(printf '{"stop_hook_active": true, "session_id": "sess-A"}' | bash hooks/session-end.sh)
assert_noop "$out" "Case B2 (stop_hook_active=true → reset counter, break the loop)"
[ -f "$FOLDER/.session-state" ] || { echo "FAIL: Case B2 should have written state"; exit 1; }
[ "$(cat "$FOLDER/.session-state")" = "sess-A 0" ] || { echo "FAIL: Case B2 state should be reset to 0, got: $(cat "$FOLDER/.session-state")"; exit 1; }

# Case B3: after reset, next 9 turns are no-op again
for i in 1 2 3 4 5 6 7 8 9; do
  out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
  assert_noop "$out" "Case B3 (post-reset turn $i)"
done
out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
assert_reminder "$out" "Case B3 (post-reset turn 10 fires again — every-N-turns continues)"

# Case B4: env override SUPER_MANUS_LOG_EVERY_N_TURNS=2 with a new session
rm -f "$FOLDER/.session-state"
out=$(printf '{"session_id":"sess-B"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=2 bash hooks/session-end.sh)
assert_noop "$out" "Case B4 (custom threshold 2, turn 1 below)"
out=$(printf '{"session_id":"sess-B"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=2 bash hooks/session-end.sh)
assert_reminder "$out" "Case B4 (custom threshold 2, turn 2 hits)"

# Case B5: switching session_id resets the counter mid-stream
rm -f "$FOLDER/.session-state"
printf '%s' '{"session_id":"sess-C"}' | bash hooks/session-end.sh >/dev/null
printf '%s' '{"session_id":"sess-C"}' | bash hooks/session-end.sh >/dev/null
[ "$(awk '{print $2}' "$FOLDER/.session-state")" = "2" ] || { echo "FAIL: Case B5 setup count should be 2, got: $(cat "$FOLDER/.session-state")"; exit 1; }
out=$(printf '{"session_id":"sess-D"}' | bash hooks/session-end.sh)
assert_noop "$out" "Case B5 (different session_id resets counter to 1, below threshold)"
[ "$(awk '{print $2}' "$FOLDER/.session-state")" = "1" ] || { echo "FAIL: Case B5 should have reset count to 1, got: $(cat "$FOLDER/.session-state")"; exit 1; }

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
