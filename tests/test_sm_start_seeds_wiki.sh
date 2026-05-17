#!/usr/bin/env bash
# Tests scripts/sm-start.sh — v0.9.8 R16 wiki/ skeleton seeding.
# /super-manus:start must create docs/super-manus/wiki/{_index.md, _log.md}
# on both fresh installs and idempotent re-runs (so projects upgrading from
# pre-v0.9.8 pick up the layer without waiting for first phase-close promote).
# Topic files (wiki/<topic>.md) MUST NOT be seeded — first promote creates
# them on demand.

set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sm_start() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "$@"
}

cd "$TMP"

# Case A: fresh project → wiki skeleton created
sm_start >/dev/null
BASE="docs/super-manus"
[ -d "$BASE/wiki" ] || { echo "FAIL: $BASE/wiki/ not created on fresh sm-start"; exit 1; }
[ -f "$BASE/wiki/_index.md" ] || { echo "FAIL: $BASE/wiki/_index.md not seeded on fresh sm-start"; exit 1; }
[ -f "$BASE/wiki/_log.md" ] || { echo "FAIL: $BASE/wiki/_log.md not seeded on fresh sm-start"; exit 1; }

# Seeded content must match template H1 (negative regression: catches "seeded
# from wrong template" / "seeded an empty file" / "template renamed")
grep -q "^# Wiki index" "$BASE/wiki/_index.md" \
  || { echo "FAIL: $BASE/wiki/_index.md missing '# Wiki index' H1 — wrong template seeded?"; exit 1; }
grep -q "^# Wiki log" "$BASE/wiki/_log.md" \
  || { echo "FAIL: $BASE/wiki/_log.md missing '# Wiki log' H1 — wrong template seeded?"; exit 1; }

# Topic files (wiki/<topic>.md) MUST NOT be seeded — first promote creates.
# Negative regression: catches future drift where someone adds runtime.md /
# paths.md / etc. as part of sm-start (rejected design choice in v0.9.8 R16
# "Initial set of topic files" — projects accumulate their own).
shopt -s nullglob
topic_files=()
for f in "$BASE/wiki"/*.md; do
  name=$(basename "$f")
  case "$name" in
    _index.md|_log.md) ;;
    *) topic_files+=("$f") ;;
  esac
done
shopt -u nullglob
[ "${#topic_files[@]}" = "0" ] || {
  echo "FAIL: sm-start MUST NOT seed wiki topic files (only _index.md + _log.md). Found: ${topic_files[*]}"
  exit 1
}

# Case B: idempotent re-run preserves existing wiki content (don't clobber
# user's accumulated rules). Write a fake rule into _log.md, re-run sm-start,
# verify the user's content survives.
echo "## [2026-05-18] promote | test entry" >> "$BASE/wiki/_log.md"
sm_start >/dev/null
grep -qF "## [2026-05-18] promote | test entry" "$BASE/wiki/_log.md" \
  || { echo "FAIL: idempotent re-run clobbered user's wiki/_log.md content — sm-start must use 'seed only if absent' semantics for wiki files"; exit 1; }

# Case C: idempotent re-run on project that pre-dates v0.9.8 (wiki/ dir
# missing) MUST seed the skeleton. Simulate by deleting wiki/ entirely then
# re-running.
rm -rf "$BASE/wiki"
sm_start >/dev/null
[ -f "$BASE/wiki/_index.md" ] \
  || { echo "FAIL: idempotent re-run on pre-v0.9.8 project (no wiki/ dir) must seed the wiki skeleton"; exit 1; }
[ -f "$BASE/wiki/_log.md" ] \
  || { echo "FAIL: idempotent re-run must also seed wiki/_log.md alongside _index.md"; exit 1; }

# Case D: partial pre-v0.9.8 state (one file present, one missing) →
# missing one gets seeded, existing one preserved.
rm "$BASE/wiki/_log.md"
echo "# CUSTOM EDIT" > "$BASE/wiki/_index.md"
sm_start >/dev/null
grep -qF "CUSTOM EDIT" "$BASE/wiki/_index.md" \
  || { echo "FAIL: existing _index.md must not be overwritten on idempotent re-run"; exit 1; }
[ -f "$BASE/wiki/_log.md" ] \
  || { echo "FAIL: missing _log.md should be seeded on idempotent re-run"; exit 1; }
grep -q "^# Wiki log" "$BASE/wiki/_log.md" \
  || { echo "FAIL: re-seeded _log.md missing '# Wiki log' H1 (wrong template)"; exit 1; }

echo OK
