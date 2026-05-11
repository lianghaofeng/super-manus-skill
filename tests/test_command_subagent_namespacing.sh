#!/usr/bin/env bash
# v0.9.2 — every `subagent_type="..."` literal in the orchestrator commands
# MUST use the plugin-namespaced form `super-manus:<agent-name>`. Bare names
# fail Claude Code's plugin agent resolution (the agents register as
# `super-manus:<name>`, not as their bare frontmatter name), causing
# first-attempt spawn errors that surface to the user as "Agent type
# 'X' not found. Available agents: ... super-manus:X ...".
#
# This test catches accidental bare-name reintroduction. Allowed forms:
#   - subagent_type="super-manus:<name>"     (canonical)
#   - subagent_type=<...>                    (templated, with placeholder)
#   - subagent_type="<...>"                  (templated, with placeholder)
# Disallowed:
#   - subagent_type="<bare-name>"            (any of our 6 agents bare)
set -euo pipefail
cd "$(dirname "$0")/.."

AGENTS=(impl-architect impl-reviewer impl-test-writer impl-code-writer reverse-architect sync-planner)

# Scan every command file
for cmd in commands/*.md; do
  for a in "${AGENTS[@]}"; do
    # Look for bare-name spawn: subagent_type="<agent>" without super-manus: prefix
    if grep -qE "subagent_type=\"${a}\"" "$cmd"; then
      echo "FAIL: ${cmd} contains bare subagent_type=\"${a}\" — must be super-manus:${a}"
      exit 1
    fi
  done
done

# Positive check: every command that DOES spawn an agent uses the namespaced form
# (so this test fails loudly if a future contributor writes subagent_type=foo with
# a typo'd plugin prefix that grep wouldn't catch above).
total_namespaced=$(grep -rE 'subagent_type="super-manus:[a-z-]+' commands/ | wc -l | tr -d ' ')
if [ "$total_namespaced" -lt 10 ]; then
  echo "FAIL: expected ≥10 namespaced subagent_type references across commands/, found ${total_namespaced}"
  exit 1
fi

echo OK
