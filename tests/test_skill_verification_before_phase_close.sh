#!/usr/bin/env bash
# Tests skills/verification-before-phase-close/SKILL.md — phase Status flips to
# `closed` only after every command in tasks/p<n>_impl.md ## Verification exits
# green. Orchestrator (NOT code-writer) runs them. ## Verification MUST contain
# both a phase-test command and a user-visible smoke command. Failed verify
# triggers systematic-debugging-in-phase.

set -euo pipefail
cd "$(dirname "$0")/.."
F="skills/verification-before-phase-close/SKILL.md"
[ -f "$F" ] || { echo "FAIL: $F missing"; exit 1; }

# Frontmatter — name + non-empty description
python3 - <<'PY' || { echo "FAIL: frontmatter check failed"; exit 1; }
import re
with open("skills/verification-before-phase-close/SKILL.md") as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
assert m, "missing YAML frontmatter block"
fm = m.group(1)
keys = {}
for line in fm.splitlines():
    if ':' in line:
        k, _, v = line.partition(':')
        keys[k.strip()] = v.strip()
assert keys.get("name") == "verification-before-phase-close", \
    f"name must be 'verification-before-phase-close', got {keys.get('name')!r}"
desc = keys.get("description", "")
assert len(desc) >= 40, f"description must be >=40 chars, got {len(desc)}"
PY

# Status flips to `closed` only after ## Verification exits green.
grep -qF "closed" "$F" || { echo "FAIL: must mention status 'closed'"; exit 1; }
grep -qF "## Verification" "$F" || { echo "FAIL: must reference ## Verification heading"; exit 1; }
grep -qiE "exits green|all green|green|exit code 0" "$F" \
  || { echo "FAIL: must say closed flips only after verification exits green"; exit 1; }

# Orchestrator (not code-writer) runs verification commands.
grep -qiF "orchestrator" "$F" || { echo "FAIL: must say orchestrator runs verify (not code-writer)"; exit 1; }
grep -qiE "not.*code-writer|orchestrator.*not.*code-writer|code-writer.*does not run" "$F" \
  || { echo "FAIL: must explicitly say code-writer does NOT run ## Verification"; exit 1; }

# ## Verification MUST include phase tests path command.
grep -qiE "phase[- ]test command|phase tests path|path to phase tests" "$F" \
  || { echo "FAIL: ## Verification must include a phase-test command"; exit 1; }
# Concrete example of phase-test invocation
grep -qE "pytest.*phase_p|jest.*phase_p|cargo test.*phase_p" "$F" \
  || { echo "FAIL: must show a concrete phase-test command example (pytest/jest/cargo)"; exit 1; }

# ## Verification MUST include user-visible smoke command.
grep -qiE "smoke|user-visible|curl|CLI|open.*page|click" "$F" \
  || { echo "FAIL: ## Verification must include a user-visible smoke command (smoke / curl / CLI / page / click)"; exit 1; }

# systematic-debugging-in-phase triggered on verify failure.
grep -qF "systematic-debugging-in-phase" "$F" \
  || { echo "FAIL: must reference systematic-debugging-in-phase skill on verify failure"; exit 1; }

echo OK
