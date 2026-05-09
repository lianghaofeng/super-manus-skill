#!/usr/bin/env bash
# Tests scripts/probe-runtime.sh — the v0.8.0 passive runtime probe consumed by
# /super-manus:reverse-prd Stage 2. The script is read-only by contract; this
# test enforces (a) the output header contract the orchestrator + agent depend
# on, (b) graceful degradation in environments missing tools / network /
# repo state, and (c) the cheat-prevention property that the script never
# invokes mutating commands.

set -euo pipefail
cd "$(dirname "$0")/.."
S=scripts/probe-runtime.sh

[ -f "$S" ] || { echo "FAIL: missing $S"; exit 1; }
[ -x "$S" ] || { echo "FAIL: $S not executable (chmod +x required)"; exit 1; }

# 1. Bash syntax must parse.
bash -n "$S" || { echo "FAIL: bash -n syntax error"; exit 1; }

# 2. Smoke run in tmp dir (no project, no git, no services). Must exit 0 quickly
#    and emit the documented headers — orchestrator + agent both parse these.
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

if ! out=$("$S" --project-root "$TMP" 2>/dev/null); then
  echo "FAIL: non-zero exit on degraded-environment smoke run"
  exit 1
fi

# 3. Required header contract — these strings ARE the API.
for h in \
  "=== RUNTIME PROBE" \
  "--- Running processes ---" \
  "--- Listening ports ---" \
  "--- Docker containers ---" \
  "--- Compose services ---" \
  "--- OpenAPI contracts ---" \
  "--- Git activity ---" \
  "--- Notes ---" \
; do
  echo "$out" | grep -qF -- "$h" || { echo "FAIL: missing header '$h'"; exit 1; }
done

# 4. Notes section must declare platform and total duration (orchestrator
#    uses 'Total duration: > 0s' to confirm the probe actually ran when
#    deciding whether to add (audit — runtime-unverified) markers).
echo "$out" | grep -qE "^Platform: " || { echo "FAIL: Notes must declare 'Platform:'"; exit 1; }
echo "$out" | grep -qE "^Total duration: [0-9]+s" || { echo "FAIL: Notes must declare 'Total duration: <N>s'"; exit 1; }
echo "$out" | grep -qE "^Skipped probes:" || { echo "FAIL: Notes must declare 'Skipped probes:'"; exit 1; }

# 5. Must accept --project-root and --ports flags without choking.
"$S" --project-root "$TMP" --ports "8000,8001" >/dev/null 2>&1 \
  || { echo "FAIL: must accept --ports flag"; exit 1; }

# 6. Cheat-prevention: script source must NOT invoke any mutating command in
#    executable code. Comment lines (^#) are excluded — the file's own header
#    documents what it does NOT do, and matching against documentation would
#    create a false positive on every contributor who mentions the rule.
#    docker compose up gating is the orchestrator's job, not the probe's.
src_code=$(grep -vE '^[[:space:]]*#' "$S")
if echo "$src_code" | grep -qE '\bdocker[[:space:]]+(run|start|restart|kill|rm)\b'; then
  echo "FAIL: probe must not invoke mutating docker commands (run/start/restart/kill/rm)"
  exit 1
fi
if echo "$src_code" | grep -qE '\bdocker[[:space:]]+compose[[:space:]]+(up|down|restart|kill|rm|stop)\b'; then
  echo "FAIL: probe must not invoke mutating docker compose commands (up/down/restart/etc.)"
  exit 1
fi
if echo "$src_code" | grep -qE '\bpsql\b'; then
  echo "FAIL: probe must not invoke psql in v0.8.0 (schema probe deferred)"
  exit 1
fi
if echo "$src_code" | grep -qE '\bgit[[:space:]]+(commit|push|reset|checkout|merge|rebase|tag)\b'; then
  echo "FAIL: probe must not invoke mutating git commands"
  exit 1
fi

# 7. Must declare the v0.8.0 contract phrase in the script header so future
#    contributors don't accidentally remove read-only invariants.
grep -qE "[Rr]ead.only|passive" "$S" || { echo "FAIL: script must self-document its read-only / passive contract"; exit 1; }

# 8. Must wrap potentially-hanging external calls with a timeout. Either
#    `--max-time` on curl directly, or the `with_timeout` helper (which uses
#    perl alarm on macOS where GNU `timeout` is missing) is acceptable.
grep -qE '(--max-time|with_timeout|\btimeout[[:space:]]+[0-9])' "$S" \
  || { echo "FAIL: must wrap potentially-hanging external calls with a timeout (curl --max-time or with_timeout helper)"; exit 1; }
grep -q 'with_timeout' "$S" \
  || { echo "FAIL: must define a with_timeout helper for cross-platform timeout (macOS lacks GNU timeout)"; exit 1; }

# 9. OpenAPI probe must guard against unbounded port scans on dev machines —
#    must NOT iterate over arbitrary detected listening ports without
#    intersecting with explicit/declared ports (otherwise WeChat / Code /
#    system services blow the 30s budget on a developer machine).
grep -qE 'declared_ports|known_infra_ports|candidate_ports' "$S" \
  || { echo "FAIL: OpenAPI probe must constrain its port set (compose/--ports/intersect-with-listening), not scan all listening ports"; exit 1; }

echo OK
