#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# Set up three fake feature folders
mkdir -p docs/super-manus/2026-05-04-alpha
mkdir -p docs/super-manus/2026-05-04-beta
mkdir -p docs/super-manus/2026-05-05-alpha-extras  # substring of 'alpha' but distinct

sm_switch() { bash "$REPO_ROOT/scripts/sm-switch.sh" "$@"; }

# Case A: exact match (post-prefix) wins, even when ambiguous as substring
out=$(sm_switch "alpha")
[ "$(cat .super-manus/active)" = "2026-05-04-alpha" ] || { echo "FAIL: exact 'alpha' should win, got $(cat .super-manus/active)"; exit 1; }

# Case B: unique substring match
out=$(sm_switch "beta")
[ "$(cat .super-manus/active)" = "2026-05-04-beta" ] || { echo "FAIL: 'beta' substring match failed"; exit 1; }

# Case C: substring matching multiple → error
if sm_switch "extra" 2>/dev/null; then
  # Wait — 'extra' only matches alpha-extras, so it should succeed (unique)
  [ "$(cat .super-manus/active)" = "2026-05-05-alpha-extras" ] || { echo "FAIL: 'extra' should match alpha-extras"; exit 1; }
else
  echo "FAIL: 'extra' should match exactly alpha-extras"; exit 1
fi

# Case D: ambiguous substring (substring of multiple) → error
# Add another feature so 'a' matches all three
mkdir -p docs/super-manus/2026-05-06-another
err=$(sm_switch "a" 2>&1 1>/dev/null) && { echo "FAIL: 'a' is substring of multiple, should error"; exit 1; } || true
echo "$err" | grep -qi "ambiguous\|multiple" || { echo "FAIL: error should mention ambiguity, got: $err"; exit 1; }

# Case E: no match → error
err=$(sm_switch "nonexistent" 2>&1 1>/dev/null) && { echo "FAIL: nonexistent name should error"; exit 1; } || true
echo "$err" | grep -qi "no match\|not found" || { echo "FAIL: error should say no match, got: $err"; exit 1; }

# Case F: no super-manus dir at all → error
rm -rf docs/super-manus
if sm_switch "anything" 2>/dev/null; then echo "FAIL: missing super-manus dir should error"; exit 1; fi

echo OK
