#!/usr/bin/env bash
set -euo pipefail

# /super-manus:sm-update.sh <module> <update-name>
#
# Seeds a new milestone-update folder under the active v0.2 feature:
#   docs/super-manus/<feature>/impl/<module>/<YYYY-MM-DD>-<update-name>/
#     ├── task_plan.md        (from templates/task_plan.md, prd.md ref → ../../../prd/<module>.md)
#     ├── findings.md         (from templates/findings.md)
#     ├── progress.md         (from templates/progress.md)
#     └── tasks/              (empty; populated by /super-manus:impl)
#
# Also flips the module's row in roadmap.md from `not-started` → `iterating`
# (a no-op if the row is already in another state — user-set state is preserved).
#
# Reads the active feature from .super-manus/active. Errors if no active feature
# or if the feature is not v0.2 layout (no prd/ folder).
#
# Used by /super-manus:brainstorm (seeds the first MVP update for the first module
# after Q&A) and /super-manus:sync (seeds a new update after a PRD edit).

if [ $# -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "usage: sm-update.sh <module> <update-name>" >&2
  exit 2
fi

module="$1"
update_name="$2"

for arg in "$module" "$update_name"; do
  if ! [[ "$arg" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "sm-update: invalid name '$arg' — must match ^[a-z0-9][a-z0-9-]*\$ (lowercase, kebab-case, no leading hyphen)" >&2
    exit 1
  fi
done

# Resolve template root: explicit env var wins, then CLAUDE_PLUGIN_ROOT, then self-locate via $0.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_ROOT="$(dirname "$SCRIPT_DIR")"
ROOT="${SUPER_MANUS_ROOT:-${CLAUDE_PLUGIN_ROOT:-$DERIVED_ROOT}}"
if [ ! -d "$ROOT/templates" ]; then
  echo "sm-update: template root not found at '$ROOT' (set SUPER_MANUS_ROOT or run via Claude Code plugin context)" >&2
  exit 1
fi

if [ ! -f .super-manus/active ]; then
  echo "sm-update: no active feature (.super-manus/active missing) — run /super-manus:start <name> first" >&2
  exit 1
fi
feature_name=$(tr -d '[:space:]' < .super-manus/active)
[ -n "$feature_name" ] || { echo "sm-update: .super-manus/active is empty" >&2; exit 1; }
case "$feature_name" in
  */*|..*|*/..*) echo "sm-update: invalid feature name in .super-manus/active: '$feature_name'" >&2; exit 1 ;;
esac

feature="docs/super-manus/$feature_name"
[ -d "$feature" ] || { echo "sm-update: feature folder missing: $feature" >&2; exit 1; }
[ -d "$feature/prd" ] || { echo "sm-update: feature is not v0.2 layout (no prd/ folder): $feature — sm-update only operates on v0.2 features" >&2; exit 1; }

today=$(date +%F)
update_folder="$feature/impl/$module/${today}-${update_name}"

if [ -e "$update_folder" ]; then
  echo "sm-update: update folder already exists: $update_folder" >&2
  exit 1
fi

cleanup_partial() {
  rm -rf "$update_folder"
}
trap cleanup_partial ERR

mkdir -p "$update_folder/tasks"

# task_plan.md: substitute <feature title> AND rewrite the prd.md hint to point
# at the per-module PRD relative to this update folder
# (impl/<module>/<update>/task_plan.md → ../../../prd/<module>.md).
src="$ROOT/templates/task_plan.md"
[ -f "$src" ] || { echo "sm-update: template missing: $src" >&2; cleanup_partial; exit 1; }
sed -e "s|<feature title>|${feature_name} / ${module} / ${update_name}|g" \
    -e "s|prd.md|../../../prd/${module}.md|g" \
    "$src" > "$update_folder/task_plan.md"

# findings.md and progress.md: substitute <feature title> only
for f in findings.md progress.md; do
  src="$ROOT/templates/$f"
  [ -f "$src" ] || { echo "sm-update: template missing: $src" >&2; cleanup_partial; exit 1; }
  sed "s|<feature title>|${feature_name} / ${module} / ${update_name}|g" "$src" > "$update_folder/$f"
done

trap - ERR

# Update roadmap.md: ensure the module has a row, and flip not-started → iterating
# without overwriting any user-set Note. If the module isn't in the table yet, append it.
roadmap="$feature/roadmap.md"
if [ -f "$roadmap" ]; then
  python3 - "$roadmap" "$module" <<'PY'
import sys, re, pathlib
path = pathlib.Path(sys.argv[1])
module = sys.argv[2]
text = path.read_text()
lines = text.splitlines(keepends=True)

# Find table rows under "## Modules". Table starts with "| Module | Status | Note |"
out = []
in_modules_table = False
saw_header = False
saw_separator = False
saw_module = False
for ln in lines:
    if ln.startswith("## Modules"):
        in_modules_table = True
        out.append(ln)
        continue
    if in_modules_table:
        if ln.startswith("## "):
            # Leaving the section — if we never saw the module row, append before leaving
            if not saw_module:
                out.append(f"| {module} | iterating | |\n")
                saw_module = True
            in_modules_table = False
            out.append(ln)
            continue
        if ln.lstrip().startswith("| Module |"):
            saw_header = True
            out.append(ln)
            continue
        if saw_header and not saw_separator and re.match(r"^\s*\|\s*-", ln):
            saw_separator = True
            out.append(ln)
            continue
        # Match a row like:  | <name> | <status> | <note> |
        m = re.match(r"^\s*\|\s*([^|<]+?)\s*\|\s*([a-z-]+)\s*\|(.*)\|\s*$", ln)
        if m:
            row_module = m.group(1).strip()
            row_status = m.group(2).strip()
            row_note = m.group(3)
            if row_module == module:
                saw_module = True
                if row_status == "not-started":
                    ln = f"| {module} | iterating |{row_note}|\n"
            elif row_module.startswith("<") and row_module.endswith(">"):
                # Placeholder template row — drop it
                continue
        out.append(ln)
    else:
        out.append(ln)

# If the loop ended while still inside the modules section and we never saw the row, append now
if in_modules_table and not saw_module:
    out.append(f"| {module} | iterating | |\n")

path.write_text("".join(out))
PY
fi

# Print the resolved folder path for the caller
echo "$(pwd)/$update_folder"
