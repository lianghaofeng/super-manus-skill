#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up an isolated v0.4 project (project-global super-manus, no per-feature wrapper)
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

# Case A: super-manus not enabled → no-op
out=$(bash hooks/session-end.sh </dev/null)
assert_noop "$out" "Case A (super-manus not enabled)"

# === v0.4 cases — project-global, no .super-manus/active, mtime-resolved active update ===
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh >/dev/null
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-update.sh "api" "mvp" >/dev/null
TODAY=$(date +%F)
UPDATE="docs/super-manus/impl/api/${TODAY}-mvp"

# Case V0.4-A: with default threshold (5), the first 4 turns are no-op; turn 5 blocks.
rm -f "$UPDATE/.session-state"
for i in 1 2 3 4; do
  out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
  assert_noop "$out" "v0.4-A (turn $i, below default threshold 5)"
done
out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-A (turn 5 hits threshold, blocks)"

# State file must live in the update folder, not at any feature root
[ -f "$UPDATE/.session-state" ] || { echo "FAIL: v0.4-A — .session-state should live in the update folder"; exit 1; }

# Case V0.4-B: stop_hook_active=true (agent done writing) → no-op AND counter reset to 0
out=$(printf '{"stop_hook_active": true, "session_id": "sess-A"}' | bash hooks/session-end.sh)
assert_noop "$out" "v0.4-B (stop_hook_active=true → reset counter, break the loop)"
[ "$(cat "$UPDATE/.session-state")" = "sess-A 0" ] || { echo "FAIL: v0.4-B state should be reset to 0, got: $(cat "$UPDATE/.session-state")"; exit 1; }

# Case V0.4-C: after reset, next 4 turns are no-op again
for i in 1 2 3 4; do
  out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
  assert_noop "$out" "v0.4-C (post-reset turn $i)"
done
out=$(printf '{"session_id":"sess-A"}' | bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-C (post-reset turn 5 fires again)"

# Case V0.4-D: env override SUPER_MANUS_LOG_EVERY_N_TURNS=2 with a new session
rm -f "$UPDATE/.session-state"
out=$(printf '{"session_id":"sess-B"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=2 bash hooks/session-end.sh)
assert_noop "$out" "v0.4-D (custom threshold 2, turn 1 below)"
out=$(printf '{"session_id":"sess-B"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=2 bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-D (custom threshold 2, turn 2 hits)"

# Case V0.4-E: switching session_id resets the counter mid-stream
rm -f "$UPDATE/.session-state"
printf '%s' '{"session_id":"sess-C"}' | bash hooks/session-end.sh >/dev/null
printf '%s' '{"session_id":"sess-C"}' | bash hooks/session-end.sh >/dev/null
[ "$(awk '{print $2}' "$UPDATE/.session-state")" = "2" ] || { echo "FAIL: v0.4-E setup count should be 2, got: $(cat "$UPDATE/.session-state")"; exit 1; }
out=$(printf '{"session_id":"sess-D"}' | bash hooks/session-end.sh)
assert_noop "$out" "v0.4-E (different session_id resets counter to 1, below threshold)"
[ "$(awk '{print $2}' "$UPDATE/.session-state")" = "1" ] || { echo "FAIL: v0.4-E should have reset count to 1, got: $(cat "$UPDATE/.session-state")"; exit 1; }

# Case V0.4-M1: SUPER_MANUS_LOG_MODE=off → never trigger, even after threshold
rm -f "$UPDATE/.session-state"
for i in $(seq 1 15); do
  out=$(printf '{"session_id":"sess-OFF"}' | SUPER_MANUS_LOG_MODE=off bash hooks/session-end.sh)
  assert_noop "$out" "v0.4-M1 mode=off, turn $i (must never trigger)"
done

# Case V0.4-M2: mode=commit → ignores turn count, fires only on unlogged commit
rm -f "$UPDATE/.session-state"
cat > "$UPDATE/progress.md" <<'EOF'
# Progress: api / mvp
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
EOF
out=$(printf '{"session_id":"sess-COMMIT"}' | SUPER_MANUS_LOG_MODE=commit bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-M2 mode=commit + unlogged commit → block on turn 1"

# Replace with progress.md where log is up-to-date → no unlogged commits
cat > "$UPDATE/progress.md" <<'EOF'
# Progress: api / mvp
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- closed P1
EOF
rm -f "$UPDATE/.session-state"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  out=$(printf '{"session_id":"sess-COMMIT2"}' | SUPER_MANUS_LOG_MODE=commit bash hooks/session-end.sh)
  assert_noop "$out" "v0.4-M2 mode=commit + log up-to-date, turn $i (must stay no-op)"
done

# Case V0.4-M3: mode=both (default) — turns hits threshold even without commit signal
rm -f "$UPDATE/.session-state"
for i in 1 2; do
  out=$(printf '{"session_id":"sess-BOTH"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=3 bash hooks/session-end.sh)
  assert_noop "$out" "v0.4-M3 mode=both, turn $i (below threshold 3)"
done
out=$(printf '{"session_id":"sess-BOTH"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=3 bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-M3 mode=both, turn 3 (turns threshold hit)"

# Case V0.4-M4: mode=both — commit signal fires before threshold
rm -f "$UPDATE/.session-state"
cat > "$UPDATE/progress.md" <<'EOF'
# Progress: api / mvp
## Completed commits
- 2026-05-05 09:00 · `abc123` · advanced P1
- 2026-05-05 13:00 · `def456` · advanced P2
## Session log
### Session 2026-05-05 #1 (10:00 – 11:00)
- closed P1
EOF
out=$(printf '{"session_id":"sess-BOTH2"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=99 bash hooks/session-end.sh)
assert_reminder "$out" "v0.4-M4 mode=both, unlogged commit triggers immediately even with N=99"

# Reminder must point at the v0.4 update path
printf '%s' "$out" > "$TMP/r.json"
UPDATE_DIR="$UPDATE" python3 - "$TMP/r.json" <<'PY' || { echo "FAIL: v0.4-M4 reminder must reference the update path"; exit 1; }
import json, os, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
ctx = d["reason"]
update = os.environ["UPDATE_DIR"]
assert f"{update}/progress.md" in ctx, f"v0.4-M4: reminder must point at {update}/progress.md, got: {ctx[:300]!r}"
assert f"{update}/task_plan.md" in ctx, f"v0.4-M4: reminder must point at {update}/task_plan.md"
PY

# Case V0.4-N1: progress.md missing → no-op (defensive)
rm "$UPDATE/progress.md"
out=$(printf '{"session_id":"sess-N1"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=1 bash hooks/session-end.sh)
assert_noop "$out" "v0.4-N1 (missing progress.md → no-op)"

# Case V0.4-N2: super-manus enabled but no impl/<m>/<u>/ yet → no-op
rm -rf docs/super-manus
SUPER_MANUS_ROOT="$TMP" bash scripts/sm-start.sh >/dev/null
out=$(printf '{"session_id":"sess-N2"}' | SUPER_MANUS_LOG_EVERY_N_TURNS=1 bash hooks/session-end.sh)
assert_noop "$out" "v0.4-N2 (no impl/<m>/<u>/ yet → no-op)"

echo OK
