#!/usr/bin/env bash
# Tests the impl-architect agent definition (agents/impl-architect.md).
# This agent is spawned by /super-manus:impl after the orchestrator's drift check
# passes; it owns drafting `${update_dir}/tasks/p<n>_impl.md` (the four-section
# phase plan) and the senior implementation-planner persona.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/impl-architect.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/impl-architect.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: impl-architect$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'impl-architect'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools' (Read/Write/Edit/Glob/Grep/Bash at minimum)"; exit 1; }

# v0.8.0: pinned model + effort routing. impl-architect is one of the three
# "thinker" agents (planning quality is what review-pipeline retries hinge on),
# so it gets effort: max. See docs/design-v0.8.md §4 for the routing rationale.
grep -qE "^model: opus$" "$F" || { echo "FAIL: frontmatter must pin 'model: opus' for the planning role"; exit 1; }
grep -qE "^effort: max$" "$F" || { echo "FAIL: frontmatter must declare 'effort: max' (planner is a top-3 thinker)"; exit 1; }

# Persona: senior implementation planner (or similar)
grep -qiE "implementation planner|implementation-planning|senior implementation" "$F" || { echo "FAIL: persona must be an implementation planner"; exit 1; }

# Documents the ten inputs the orchestrator passes
for input in project_root module update_dir phase_number phase_name module_prd_path task_plan_path findings_path progress_path lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Deliverable: writes ${update_dir}/tasks/p<n>_impl.md (NOT chat)
grep -qF "tasks/p" "$F" || { echo "FAIL: must specify the tasks/p<n>_impl.md write target"; exit 1; }
grep -qF "_impl.md" "$F" || { echo "FAIL: must specify the p<n>_impl.md filename pattern"; exit 1; }
grep -qiE "do NOT print|not print to chat|do not print" "$F" || { echo "FAIL: must explicitly forbid printing the file to chat"; exit 1; }

# Five exact H2 section names — Objective / Approach / Edge cases / Files touched / Verification (v0.9.0)
for h in "## Objective" "## Approach" "## Edge cases" "## Files touched" "## Verification"; do
  grep -qF "$h" "$F" || { echo "FAIL: agent must document section '$h'"; exit 1; }
done

# v0.9.0: section header rename "Four H2" → "Five H2"
grep -qiE "Five H2 sections|five H2|5 H2" "$F" \
  || { echo "FAIL: v0.9.0 must update the section heading to 'Five H2 sections' (was 'Four H2 sections')"; exit 1; }

# Drift check protocol references — LSP, double-source, LSP-unavailable fallback
grep -qF "Drift check protocol" "$F" || { echo "FAIL: must reference the using-sm Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: must mention LSP as a structural-inference primary tool"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: must articulate the double-source / cross-check rule"; exit 1; }
grep -qiE "LSP unavailable|LSP not available|no language server" "$F" || { echo "FAIL: must specify the LSP-unavailable fallback path"; exit 1; }

# Idempotency: do not overwrite filled phase plans
grep -qiE "idempotent|idempotency|do NOT overwrite|already drafted" "$F" || { echo "FAIL: must specify idempotency — don't overwrite filled phase plans"; exit 1; }

# Write barrier: Edit/Write must never target the plugin template (CLAUDE_PLUGIN_ROOT is read-only).
# Without this barrier the architect "edits" templates/phase_plan.md in-place to substitute
# placeholders, which trips a sensitive-file permission prompt under the plugin cache.
grep -qF 'CLAUDE_PLUGIN_ROOT' "$F" || { echo "FAIL: must mention CLAUDE_PLUGIN_ROOT in the write-barrier rule"; exit 1; }
grep -qiE "READ-ONLY|read.only|never .{0,30}(Edit|Write).{0,30}(template|CLAUDE_PLUGIN_ROOT)|do NOT (Edit|Write).{0,30}(template|CLAUDE_PLUGIN_ROOT)" "$F" || { echo "FAIL: must declare templates/CLAUDE_PLUGIN_ROOT as read-only / forbid Edit on the template"; exit 1; }
grep -qiE "seed.*template|sed.*template|Bash.*sed" "$F" || { echo "FAIL: must specify the Bash+sed seeding procedure (so Edit isn't applied to the template)"; exit 1; }

# Budget: ≤5 LSP, ≤10 grep/Read
grep -qiE "≤5 LSP|5 LSP" "$F" || { echo "FAIL: must mention ≤5 LSP call ceiling"; exit 1; }
grep -qiE "≤10|10 grep|grep / Read" "$F" || { echo "FAIL: must mention ≤10 grep/Read ceiling"; exit 1; }
grep -qiF "budget" "$F" || { echo "FAIL: must specify a source-reading budget"; exit 1; }

# "No code in the phase plan" rule
grep -qiE "no code in the phase plan|do not write code|No code\b|not write code" "$F" || { echo "FAIL: must include 'no code in the phase plan' rule"; exit 1; }

# Returns ONE summary line
grep -qiE "summary line|one[- ]line summary|one summary line|return.*one summary" "$F" || { echo "FAIL: must specify the agent returns ONE summary line"; exit 1; }
grep -qiE "drafted.*p<n>_impl|drafted p" "$F" || { echo "FAIL: must specify the 'drafted p<n>_impl.md' summary form"; exit 1; }

# (audit) policy — single-source / no bulk
grep -qiE "single.source|do NOT bulk-mark|bulk[ -]mark" "$F" || { echo "FAIL: must restrict (audit) markers (single-source only, no bulk)"; exit 1; }

# Phase-test path constraint — Files touched MUST require an entry under ${update_dir}/tests/
# (this prevents architects from co-opting the project's existing test suite as the phase target,
# which silently breaks v0.5 phase-test isolation — see skills/tdd-in-phases/SKILL.md)
grep -qF 'phase_p<n>_<verb>_<noun>' "$F" || { echo "FAIL: must require phase-test filename pattern phase_p<n>_<verb>_<noun>"; exit 1; }
grep -qF '${update_dir}/tests/' "$F" || { echo "FAIL: must require phase tests under \${update_dir}/tests/"; exit 1; }
grep -qiE "co-opt|do NOT co-opt|don't co-opt" "$F" || { echo "FAIL: must explicitly forbid co-opting the existing regression suite as the phase target"; exit 1; }
grep -qiE "not auto-discovered|NOT auto-discovered|auto-discovered" "$F" || { echo "FAIL: must explain phase tests are not auto-discovered (the load-bearing reason)"; exit 1; }

# Verification MUST require BOTH a phase-test path command AND a user-visible smoke command
grep -qiE "phase[- ]test path command|explicit path|phase-test path" "$F" || { echo "FAIL: ## Verification must require an explicit phase-test path command"; exit 1; }
grep -qiE "smoke command|user-visible" "$F" || { echo "FAIL: ## Verification must require a user-visible smoke command"; exit 1; }

# === v0.7.4 additive assertions ===========================================
# Architect must document the prior_reflections input + a procedure step that
# treats Heuristic lines as a checklist for this phase's plan.
grep -qF "prior_reflections" "$F" \
  || { echo "FAIL: v0.7.4 must document the prior_reflections input"; exit 1; }
grep -qF "Heuristic" "$F" \
  || { echo "FAIL: v0.7.4 must reference the Heuristic line as the load-bearing element of prior_reflections"; exit 1; }
grep -qiE "checklist|honor.*Heuristic" "$F" \
  || { echo "FAIL: v0.7.4 must say the architect treats Heuristic lines as a checklist (not free reading)"; exit 1; }

# === v0.9.0 additive assertions ===========================================
# Architect must enumerate concrete edge cases anchored in PRD ## Quality bar
# / ## Risks, with vague labels (error_handling: yes) explicitly called out as
# rejection-worthy. The reviewer pre-test relies on this enumeration to walk
# bullets and check coverage downstream.
grep -qiE "3.{0,3}5 bullets" "$F" \
  || { echo "FAIL: v0.9.0 must specify 3-5 bullets for ## Edge cases"; exit 1; }
grep -qiE "anchored|anchor" "$F" \
  || { echo "FAIL: v0.9.0 must require Edge cases bullets to be anchored (PRD ## Quality bar / ## Risks / named failure mode)"; exit 1; }
grep -qF "## Quality bar" "$F" \
  || { echo "FAIL: v0.9.0 must reference PRD ## Quality bar as a primary anchor source for Edge cases"; exit 1; }
grep -qF "## Risks" "$F" \
  || { echo "FAIL: v0.9.0 must reference PRD ## Risks as a primary anchor source for Edge cases"; exit 1; }
grep -qiE "concrete .{0,10}testable|testable|concrete failure mode" "$F" \
  || { echo "FAIL: v0.9.0 must require Edge cases bullets to be concrete + testable"; exit 1; }
grep -qiE "error_handling: yes|vague.{0,30}untestable|untestable" "$F" \
  || { echo "FAIL: v0.9.0 must explicitly reject vague labels (error_handling: yes) as Edge cases content"; exit 1; }
grep -qiE "happy.path scaffolding|pure happy.path" "$F" \
  || { echo "FAIL: v0.9.0 must document the pure-happy-path scaffolding exception (single-bullet form)"; exit 1; }

# Legacy 4-section migration path — architect must handle plans that pre-date
# v0.9.0 (no ## Edge cases) by inserting the section in place, NOT overwriting.
grep -qiE "legacy .{0,10}plan|legacy 4.section|pre.dat" "$F" \
  || { echo "FAIL: v0.9.0 must document the legacy 4-section migration path"; exit 1; }
grep -qiE "insert .{0,30}Edge cases|added Edge cases" "$F" \
  || { echo "FAIL: v0.9.0 must specify in-place insertion of ## Edge cases for legacy plans (not full overwrite)"; exit 1; }

# Negative regression: stale "four-section" copy must NOT describe the v0.9.0
# deliverable. The phrase is allowed only in legacy-context references that
# explicitly tag it as pre-v0.9.0 / v0.8.x. Anywhere else → contradiction with
# the new five-section reality.
# Allowed forms: "was four-section", "pre-v0.9.0", "4-section" with v0.8.x tag.
# Disallowed: "the four-section markdown file", "Fill the four sections", "four-section template population".
grep -qE "four-section markdown file|Fill the four sections|four-section template population" "$F" \
  && { echo "FAIL: v0.9.0 must NOT describe the deliverable as 'four-section' (the architect now writes 5 sections)"; exit 1; } || true

# B3: (audit) policy must explicitly extend to ## Edge cases (reviewer pre-test
# enforces (audit) resolution there; without policy mention, architect may not
# know the policy applies to the new section).
grep -qiE "applies.{0,30}Edge cases|Edge cases.{0,30}\(audit\)|\(audit\) policy.{0,200}Edge cases" "$F" \
  || { echo "FAIL: v0.9.0 (audit) policy must explicitly extend to ## Edge cases"; exit 1; }

# D: scaffolding-clause challenge handler in re-spawn protocol. Architect must
# have a specific path for "reviewer challenged my Pure happy-path scaffolding
# clause" — concede or reject-with-evidence. Generic "address each issue" is
# too weak (per cross-agent audit Agent #4 finding).
grep -qiE "scaffolding.{0,15}challenge|challenged.{0,30}scaffolding|scaffolding.clause challenge" "$F" \
  || { echo "FAIL: v0.9.0 architect re-spawn handler must have a specific path for scaffolding-clause challenges"; exit 1; }
grep -qiE "concede|replace .{0,30}scaffolding|reject with evidence|kept scaffolding exception" "$F" \
  || { echo "FAIL: v0.9.0 scaffolding-challenge protocol must specify concede vs reject-with-evidence (not silent ignore)"; exit 1; }

# === v0.9.4 R5: two-pass spawn + existing_code_facts injection ============
# Architect runs in two modes (pass=1 emits files_touched YAML only; pass=2
# drafts the full plan with orchestrator-computed existing_code_facts as
# non-negotiable factual context). On re-spawn, previous_architect_draft is
# injected as a fact block (replaces "trust the agent to Read its prior draft").

# Pass discipline section heading exists
grep -qiE "^## Pass discipline|Pass discipline.*two-pass" "$F" \
  || { echo "FAIL: v0.9.4 R5 must declare a ## Pass discipline (two-pass spawn) section"; exit 1; }

# Both pass modes documented
grep -qE "pass=1|Pass 1" "$F" \
  || { echo "FAIL: v0.9.4 R5 must document Pass 1 (pass=1) mode"; exit 1; }
grep -qE "pass=2|Pass 2" "$F" \
  || { echo "FAIL: v0.9.4 R5 must document Pass 2 (pass=2) mode"; exit 1; }

# Pass 1 deliverable: YAML at .pass1_files_touched_p<n>.yml
grep -qF ".pass1_files_touched_p" "$F" \
  || { echo "FAIL: v0.9.4 R5 must write Pass 1 YAML to .pass1_files_touched_p<n>.yml"; exit 1; }
grep -qE "files_touched:" "$F" \
  || { echo "FAIL: v0.9.4 R5 must specify YAML schema starts with 'files_touched:'"; exit 1; }

# Pass 1 forbids drafting other sections
grep -qiE "do NOT draft.*Approach|JUST scoping|Pass 1 is JUST" "$F" \
  || { echo "FAIL: v0.9.4 R5 Pass 1 must explicitly forbid drafting ## Approach/Edge/Verification"; exit 1; }

# Pass 2 inputs: pass1_files_touched + existing_code_facts
grep -qF "pass1_files_touched" "$F" \
  || { echo "FAIL: v0.9.4 R5 Pass 2 must receive pass1_files_touched as input"; exit 1; }
grep -qF "existing_code_facts" "$F" \
  || { echo "FAIL: v0.9.4 R5 Pass 2 must receive existing_code_facts as input"; exit 1; }

# existing_code_facts is non-negotiable factual context
grep -qiE "non-negotiable|ground truth|factual context" "$F" \
  || { echo "FAIL: v0.9.4 R5 must declare existing_code_facts as non-negotiable factual context"; exit 1; }

# Add vs replace example — the core state-blind bug R5 prevents
grep -qiE "add.*foo|replace.*foo|add vs replace|add.{0,5}vs.{0,5}replace" "$F" \
  || { echo "FAIL: v0.9.4 R5 must give the add-vs-replace example (the state-blind bug R5 prevents)"; exit 1; }

# previous_architect_draft input on re-spawn
grep -qF "previous_architect_draft" "$F" \
  || { echo "FAIL: v0.9.4 R5 must document previous_architect_draft input (re-spawn fact injection)"; exit 1; }

# Procedure step 0 branches on pass
grep -qiE "Branch on .{0,5}pass|pass mode|pass=1.{0,40}pass=2|If .{0,5}pass=1" "$F" \
  || { echo "FAIL: v0.9.4 R5 procedure must branch on pass input (step 0 or equivalent)"; exit 1; }

echo OK
