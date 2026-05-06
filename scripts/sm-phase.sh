#!/usr/bin/env bash
set -euo pipefail

# /super-manus:phase <n> — open or seed the per-phase implementation plan tasks/p<n>_impl.md
# for the active feature. Pure persistence: copies template, substitutes <n>
# and <phase name> from task_plan.md ## Phases. Idempotent: if the file already
# exists, prints its path and exits 0 without modifying it.

if [ $# -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: sm-phase.sh <phase-number>" >&2
  exit 2
fi

n="$1"
if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
  echo "sm-phase: invalid phase number '$n' — must be a positive integer" >&2
  exit 1
fi

# Resolve template root: explicit env var wins, then CLAUDE_PLUGIN_ROOT, then self-locate via $0.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_ROOT="$(dirname "$SCRIPT_DIR")"
ROOT="${SUPER_MANUS_ROOT:-${CLAUDE_PLUGIN_ROOT:-$DERIVED_ROOT}}"
if [ ! -f "$ROOT/templates/phase_plan.md" ]; then
  echo "sm-phase: template root not found at '$ROOT' (set SUPER_MANUS_ROOT or run via Claude Code plugin context)" >&2
  exit 1
fi

if [ ! -f .super-manus/active ]; then
  echo "sm-phase: no active super-manus feature (run /super-manus:start <name> first)" >&2
  exit 1
fi
basename=$(cat .super-manus/active)
folder="docs/super-manus/${basename}"
if [ ! -d "$folder" ]; then
  echo "sm-phase: active feature folder missing: $folder" >&2
  exit 1
fi

plan="$folder/task_plan.md"
if [ ! -f "$plan" ]; then
  echo "sm-phase: $plan missing — feature folder is corrupt" >&2
  exit 1
fi

# Extract the phase name from the Phases table row whose first cell is exactly $n.
# Phases table format: | # | Name | Status | Notes |
phase_name=$(awk -v want="$n" '
  /^## Phases/ { in_table=1; next }
  in_table && /^## / { in_table=0 }
  in_table && /^\|[^-]/ {
    # split on |, trim each cell
    nf = split($0, c, "|")
    # cells are c[2..nf-1]; c[2] is #, c[3] is Name
    gsub(/^[ \t]+|[ \t]+$/, "", c[2])
    gsub(/^[ \t]+|[ \t]+$/, "", c[3])
    if (c[2] == want) { print c[3]; exit }
  }
' "$plan")

if [ -z "$phase_name" ]; then
  echo "sm-phase: phase $n not found in $plan ## Phases table" >&2
  exit 1
fi

target="$folder/tasks/p${n}_impl.md"
if [ -f "$target" ]; then
  # Idempotent: just print the path, leave content untouched
  echo "$(pwd)/$target"
  exit 0
fi

mkdir -p "$folder/tasks"
# Substitute <n> and <phase name> in the template. Pipe-delimited sed to avoid
# colliding with content. <n> is numeric so safe; <phase name> may contain
# punctuation but not pipes by convention — task_plan.md table cells exclude |.
sed -e "s|<n>|${n}|g" -e "s|<phase name>|${phase_name}|g" \
  "$ROOT/templates/phase_plan.md" > "$target"

echo "$(pwd)/$target"
