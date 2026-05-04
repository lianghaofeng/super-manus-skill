#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: sm-switch.sh <feature-name-or-substring>" >&2
  exit 2
fi

name="$1"
base="docs/super-manus"

if [ ! -d "$base" ]; then
  echo "sm-switch: no super-manus features in this project (looked in $base)" >&2
  exit 1
fi

# Collect existing folder basenames, stripping the YYYY-MM-DD- prefix to get the user-facing name
declare -a all_basenames=()
declare -a candidates=()
for d in "$base"/*/; do
  [ -d "$d" ] || continue
  bn=$(basename "$d")
  all_basenames+=("$bn")
  # Strip the date prefix to compare against user input
  short="${bn#????-??-??-}"
  # Exact match takes priority — handle in two passes
  if [ "$short" = "$name" ]; then
    # Exact match wins immediately
    mkdir -p .super-manus
    echo "$bn" > .super-manus/active
    echo "Switched to: $base/$bn"
    exit 0
  fi
done

# No exact match: do substring matching
for bn in "${all_basenames[@]}"; do
  short="${bn#????-??-??-}"
  case "$short" in
    *"$name"*) candidates+=("$bn") ;;
  esac
done

case ${#candidates[@]} in
  0)
    echo "sm-switch: no match for '$name' in $base. Existing features:" >&2
    for bn in "${all_basenames[@]}"; do echo "  - $bn" >&2; done
    exit 1
    ;;
  1)
    bn="${candidates[0]}"
    mkdir -p .super-manus
    echo "$bn" > .super-manus/active
    echo "Switched to: $base/$bn"
    ;;
  *)
    echo "sm-switch: ambiguous — '$name' matches multiple features:" >&2
    for bn in "${candidates[@]}"; do echo "  - $bn" >&2; done
    exit 1
    ;;
esac
