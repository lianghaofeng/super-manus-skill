#!/usr/bin/env bash
# Runs every test_*.sh in tests/. Exits non-zero if any fail.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
total=0
declare -a failures=()
for t in tests/test_*.sh; do
  [ -f "$t" ] || continue
  total=$((total + 1))
  name=$(basename "$t")
  printf '=== %-45s ' "$name"
  if bash "$t" >/tmp/sm-test.out 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    failures+=("$name")
    fail=$((fail + 1))
    echo "--- output ---"
    cat /tmp/sm-test.out
    echo "--- /output ---"
  fi
done

echo
if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail of $total test(s):"
  for f in "${failures[@]}"; do echo "  - $f"; done
  exit 1
fi
echo "ALL PASS ($total tests)"
