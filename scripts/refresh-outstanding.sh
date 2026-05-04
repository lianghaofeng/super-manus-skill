#!/usr/bin/env bash
# refresh-outstanding.sh — regenerate the `## Outstanding` section of
# <feature-folder>/progress.md from the Phases table in
# <feature-folder>/task_plan.md. Pure POSIX shell + awk + sed.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: refresh-outstanding.sh <feature-folder>" >&2
  exit 2
fi

FOLDER="$1"
[ -d "$FOLDER" ] || { echo "refresh-outstanding: folder not found: $FOLDER" >&2; exit 1; }
[ -f "$FOLDER/task_plan.md" ] || { echo "refresh-outstanding: task_plan.md not found in $FOLDER" >&2; exit 1; }
[ -f "$FOLDER/progress.md" ] || { echo "refresh-outstanding: progress.md not found in $FOLDER" >&2; exit 1; }

# Extract non-closed phase rows from the markdown table.
# Skip the header row (field 2 == "#") and the separator row (field 2 made of dashes).
phase_lines=$(awk -F'|' '
  /^[[:space:]]*\|/ {
    f2=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f2)
    if (f2 == "" || f2 ~ /^-+$/) next
    if (f2 == "#") next
    f3=$3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f3)
    f4=$4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", f4)
    if (f4 == "closed") next
    if (f4 == "") next
    printf "- [P%s] %s (%s)\n", f2, f3, f4
  }
' "$FOLDER/task_plan.md")

if [ -z "$phase_lines" ]; then
  body='(no outstanding phases)'
else
  body="$phase_lines"
fi

TMP_SECTION=$(mktemp)
TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_SECTION" "$TMP_OUT" "$TMP_OUT.norm"' EXIT

printf '## Outstanding\n\n<!-- auto-regenerated from task_plan.md by scripts/refresh-outstanding.sh; do not edit by hand -->\n\n%s\n' "$body" > "$TMP_SECTION"

if grep -q "^## Outstanding$" "$FOLDER/progress.md"; then
  # Replace the existing Outstanding section in place.
  awk -v section_file="$TMP_SECTION" '
    function emit_section(   line) {
      while ((getline line < section_file) > 0) print line
      close(section_file)
    }
    BEGIN { in_section = 0 }
    /^## / {
      if (in_section) {
        # Reached the next H2 — emit the new section, then fall through to print this line.
        emit_section()
        in_section = 0
      }
      if ($0 == "## Outstanding") {
        in_section = 1
        next
      }
    }
    !in_section { print }
    END {
      if (in_section) emit_section()
    }
  ' "$FOLDER/progress.md" > "$TMP_OUT"
else
  # No Outstanding heading — append at EOF with a blank-line separator.
  cat "$FOLDER/progress.md" > "$TMP_OUT"
  # Ensure trailing newline before appending.
  if [ -s "$TMP_OUT" ] && [ "$(tail -c 1 "$TMP_OUT")" != "" ]; then
    printf '\n' >> "$TMP_OUT"
  fi
  printf '\n' >> "$TMP_OUT"
  cat "$TMP_SECTION" >> "$TMP_OUT"
fi

# Normalize trailing whitespace: strip any trailing blank lines, then ensure exactly one final \n.
awk '
  { lines[NR] = $0 }
  END {
    n = NR
    while (n > 0 && lines[n] == "") n--
    for (i = 1; i <= n; i++) print lines[i]
  }
' "$TMP_OUT" > "$TMP_OUT.norm"
mv "$TMP_OUT.norm" "$FOLDER/progress.md"
rm -f "$TMP_OUT" "$TMP_SECTION"
trap - EXIT
