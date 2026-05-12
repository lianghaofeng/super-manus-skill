#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/prd-update.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4: no .super-manus/active state file
grep -qF ".super-manus/active" "$F" && { echo "FAIL: prd-update.md must NOT reference .super-manus/active in v0.4"; exit 1; } || true

# v0.4: project-global PRD root
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ as the v0.4 project-global PRD root"; exit 1; }

# Must operate on a single per-module PRD file
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must reference prd/<module>.md (per-module PRD)"; exit 1; }

# The 5 surgical-edit options must all be documented
for opt in Tighten Split Demote Exclude Add; do
  grep -qF "$opt" "$F" || { echo "FAIL: must document the '$opt' edit option"; exit 1; }
done

# Hard constraints — no changelog markers, no multi-section rewrites, ≤2000 words
grep -qiF "no changelog" "$F" || { echo "FAIL: must forbid changelog markers"; exit 1; }
grep -qiF "minimum" "$F" || { echo "FAIL: must call out minimum / surgical edit constraint"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for the module file"; exit 1; }
grep -qiF "brainstorm" "$F" || { echo "FAIL: must redirect multi-section rewrites to /super-manus:brainstorm"; exit 1; }

# Must write a paired findings.md decision entry in the active update folder
grep -qF "findings.md" "$F" || { echo "FAIL: must write a paired findings.md decision entry"; exit 1; }

# Must NOT write to progress.md (hook-managed)
grep -qiF "progress.md" "$F" || { echo "FAIL: must mention progress.md (specifically: not to write to it)"; exit 1; }

# Must redirect tech-design changes back to impl/<module>/<update>/tasks/
grep -qiF "tech" "$F" || { echo "FAIL: must distinguish product vs tech changes"; exit 1; }

# v0.4: per-module impl path is project-global (no <feature>/ wrapper)
grep -qF "docs/super-manus/impl/<module>" "$F" || { echo "FAIL: must reference docs/super-manus/impl/<module>/ (v0.4 path, no feature wrapper)"; exit 1; }

# Tighten / Demote options must verify the affected bullet against the actual code via using-sm's Drift check protocol
grep -qF "Drift check protocol" "$F" || { echo "FAIL: prd-update.md must reference using-sm's Drift check protocol for Tighten/Demote verification"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: prd-update.md must use LSP to verify the bullet against current code (not just trust the user)"; exit 1; }

# === v0.9.6 R11: Post-edit PRD→spec topic-overlap check ====================
# After the PRD edit lands, scan sibling <module>.spec.md for shared-topic
# bullets. Soft warning (NOT a hard gate); honors R7 OQ3 ratification that
# PRD ↔ spec overlap is upstream/downstream, not drift.

# Section heading exists
grep -qiE "^## Post-edit topic-overlap check|## Post-edit topic.overlap" "$F" \
  || { echo "FAIL: v0.9.6 R11 must declare a '## Post-edit topic-overlap check' section"; exit 1; }
# Skip if spec missing (don't fire false positive on missing-spec — that's the gate's job)
grep -qiE "Skip if spec missing|spec doesn.t exist|skip this whole section" "$F" \
  || { echo "FAIL: v0.9.6 R11 must skip the check when prd/<module>.spec.md is absent"; exit 1; }
# Tokenization rule with stopwords
grep -qiE "tokenize|noun.*verb|alphanumeric|stopword" "$F" \
  || { echo "FAIL: v0.9.6 R11 must define a tokenization rule for the edited bullet"; exit 1; }
# Threshold for hit
grep -qiE "≥3 distinct|3 distinct token|threshold.*3" "$F" \
  || { echo "FAIL: v0.9.6 R11 must specify a hit threshold (≥3 distinct tokens) to filter noise"; exit 1; }
# AskUserQuestion with 3 options (open / confirm / soft-acknowledge)
grep -qiE "AskUserQuestion" "$F" \
  || { echo "FAIL: v0.9.6 R11 must use AskUserQuestion when overlap is detected"; exit 1; }
grep -qiE "Open spec to inspect|Confirm consistent|soft-acknowledged" "$F" \
  || { echo "FAIL: v0.9.6 R11 must offer at least 3 user actions (open / confirm / soft-ack)"; exit 1; }
# Logging to drift_log.md ## Spec drift with acknowledged-soft Resolution
grep -qiE "drift_log.md.*## Spec drift|## Spec drift.*drift_log" "$F" \
  || { echo "FAIL: v0.9.6 R11 must log to drift_log.md ## Spec drift section"; exit 1; }
grep -qiE "acknowledged-soft|acknowledged.soft" "$F" \
  || { echo "FAIL: v0.9.6 R11 must use 'acknowledged-soft' Resolution (NOT pending — preserves audit without hard-gating per R7 OQ3)"; exit 1; }
# Hard-gate exemption explicit
grep -qiE "NOT enter Pass 3|NOT.*hard gate|does NOT gate|R7 OQ3" "$F" \
  || { echo "FAIL: v0.9.6 R11 must explicitly state the soft warning does NOT enter the hard gate (R7 OQ3 honor)"; exit 1; }
# Escalation path: user can manually change Resolution from acknowledged-soft to pending if real conflict
grep -qiE "flip to.*pending|genuinely conflicts.*pending|pending.*real drift|change THAT row.*pending|Resolution cell.*pending|escalation.*hard drift" "$F" \
  || { echo "FAIL: v0.9.6 R11 must document a user escalation path (manually change Resolution from 'acknowledged-soft' to 'pending') when overlap turns out to be a real conflict"; exit 1; }
# Skip logging on no overlap (silence is the default, no noise)
grep -qiE "silence is the default|skip.*logging|don.t log.*no overlap" "$F" \
  || { echo "FAIL: v0.9.6 R11 must skip logging on no overlap (silence as default; no 'no overlap detected' noise rows)"; exit 1; }

# === v0.9.6 R11.1: symmetric resolution paths after choice (a) ============
# (a) "open spec to inspect" must have a follow-up AskUserQuestion with 4
# equal-weight options. Both "fix spec" AND "revert/refine PRD" are
# first-class — R7 OQ3 ratification: PRD ↔ spec is upstream/downstream
# symmetric, not master/slave. Pre-judging "spec is the side to fix" would
# violate that symmetry.

# Section heading exists
grep -qiE "^### After choice \(a\)|## After choice \(a\)|symmetric resolution paths" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare a follow-up section after (a) for symmetric resolution"; exit 1; }
# 4 equal-weight options — both fix-spec and fix-PRD are first-class
grep -qiE "fix spec now|Spec is stale.*fix spec" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (i) must offer 'fix spec now' (inline spec-update)"; exit 1; }
grep -qiE "fix spec later|spec-edit-deferred" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (ii) must offer 'fix spec later' (acknowledged-soft: spec-edit-deferred)"; exit 1; }
grep -qiE "PRD edit was wrong|revert.*PRD|refine.*PRD edit" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iii) must offer 'revert/refine PRD' as a first-class option (R7 OQ3 symmetric direction)"; exit 1; }
grep -qiE "Both are correct.*voice|confirmed-consistent" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iv) must offer 'both correct in their voices' option"; exit 1; }
# Inline-execution discipline (drive.md pattern: read command body, execute in main thread, no sub-skill nesting)
grep -qiE "inline-execut|inline execut|do NOT spawn.*sub-Skill|drive.*pattern|nest.*slash command" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare inline-execution discipline (no nested slash commands; main-thread execution like drive.md)"; exit 1; }
# Resolution-precedence rule — chained command's own logging wins, no double-write
grep -qiE "chained command.*precedence|don.t double-write|takes precedence|NOT.*acknowledged-soft" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must specify chained command's logging takes precedence (no double-write of Resolution)"; exit 1; }
# Edit-irreversibility caveat — user must be told that the original Edit can't be auto-reverted
grep -qiE "cannot be auto-reverted|Edit is destructive|manually restore.*prior wording" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 (iii) must surface that the original Edit can't be auto-reverted (destructive tool); user must tighten or manually restore"; exit 1; }

# === v0.9.6 R11.1 row-write timing discipline (load-bearing) ===============
# R11 must NOT write a drift_log row at detection time — row writes are
# deferred until the user's terminal choice is known. Otherwise:
#   - (i)/(iii) branches end up with TWO rows (R11's `acknowledged-soft:` +
#     chained command's `spec-update: <section>` / `prd-update: <letter>`)
#   - Mid-flow abandonment leaves a stale `acknowledged-soft:` orphan

grep -qiE "Row-write timing|R11 does NOT write.*at the moment of overlap detection|deferred until the user's.*choice" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must declare row-write-timing discipline (no row written until terminal user choice is known)"; exit 1; }
# Branch (a→i) and (a→iii) must explicitly NOT write an R11 row (chained command owns it)
grep -qiE "no R11 row.*chained|chained.*writes.*own row.*from scratch|R11 stays out of.*drift_log.md" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must specify that (a→i) and (a→iii) branches let the chained command write the row from scratch (no double-write)"; exit 1; }
# Logging table must distinguish "where row lives" — prd-update side should reflect (a→iii) goes to opposite section
grep -qF "## PRD drift" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 logging table (in prd-update.md) must reference ## PRD drift (the OPPOSITE section, used when (a→iii) chained command writes its own row)"; exit 1; }
# Hard-gates? column or equivalent — every row variant must answer the gating question
grep -qiE "Hard-gates|enter.*hard gate|blocks.*roadmap" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 logging table should make hard-gate status explicit per branch"; exit 1; }
# Pass 3 equality match (NOT substring) — load-bearing for acknowledged-soft exemption
grep -qiE "case-insensitive equality.*NOT substring|equality.*NOT substring|equals.*case-insensitive" "$F" \
  || { echo "FAIL: v0.9.6 R11.1 must clarify Pass 3 uses case-insensitive EQUALITY (not substring grep), so 'acknowledged-soft:' rows are exempt by construction"; exit 1; }

# === v0.9.7 R15: drift_log row append uses 5-column schema with Author ===
# prd-update.md writes drift_log rows in branches (b)/(c)/(a→ii)/(a→iv). The full
# row-template example must use the 5-column form with <author> as the second cell.
grep -qF "| <YYYY-MM-DD> | <author> | <module> |" "$F" \
  || { echo "FAIL: v0.9.7 R15 — prd-update.md must show a 5-column drift_log row template with <author> as the second cell (branches b/c/a→ii/a→iv)"; exit 1; }
grep -qF "git config user.name" "$F" \
  || { echo "FAIL: v0.9.7 R15 — prd-update.md must document Author cell source ('git config user.name')"; exit 1; }
grep -qiE "Date \| Author \| Module \| Conflict \| Resolution|5 column|5-column" "$F" \
  || { echo "FAIL: v0.9.7 R15 — prd-update.md must call out the 5-column drift_log schema explicitly so writers know the cell order"; exit 1; }

echo OK
