# super-manus — Design Doc (v0.6)

> Current design. Small additive change on top of v0.5.
>
> Supersedes [docs/design-v0.5.md](design-v0.5.md) (v0.5 — 3-agent impl pipeline + e2e regression suite). Layout, agents, skills, hooks, and end-of-update drift gate are unchanged from v0.5. Only the positioning of `/super-manus:prd-update` widens.

## 1. What changed from v0.5

v0.5 nailed the 3-agent impl pipeline but left a discoverability gap on the PRD-edit side:

- **`/super-manus:prd-update` was framed as drift-absorption-only.** Its description said "absorb a confirmed implementation deviation"; its first read step asked "What's the deviation you want PRD to absorb?". Users with a forward intent ("I want to add a new capability to module X before writing code") had no obvious slash command — the README told them to hand-edit `prd/<module>.md` directly, then run `/super-manus:sync`. That works, but it's the only PRD-touching workflow that requires raw-text editing, which is friction for users who think in conversational increments.
- **The 5-option workflow (Tighten / Split / Demote / Exclude / Add) was already capable of forward edits** — `Add` literally adds a new bullet, `Tighten` literally rewords an existing one. The framing just hid it. v0.6 promotes the existing capability.

v0.6 closes this gap by **repositioning `/super-manus:prd-update` to handle both forward iteration and drift absorption** under one command, with mode-dependent bookkeeping. No new commands; no name change; no schema change.

This is option **A** of the design discussion: reuse `prd-update` rather than introduce `/super-manus:propose` or `/super-manus:add-feature`. Reasoning:

- The 5 options already cover both intents.
- Two commands doing nearly identical things (`add-feature` + `prd-update`) would force users to learn the boundary and re-learn it on each tool upgrade.
- Single command, two modes, dispatch via `prd_drift.md` row presence — zero ambiguity at runtime.

## 2. Mode dispatch

Inside `/super-manus:prd-update <module>`, after reading `prd/<module>.md`, the orchestrator checks `prd_drift.md` for a pending row matching `Module = <module>`:

```
+-- pending row found -------+      +-- no pending row ----------+
|  drift absorption mode     |      |  forward iteration mode    |
|                            |      |                            |
|  - lead question:          |      |  - lead question:          |
|    "The conflict is X."    |      |    "Editing prd/<m>.md to  |
|                            |      |     <intent>."             |
|  - the 5 options unchanged |      |  - the 5 options unchanged |
|                            |      |                            |
|  after edit:               |      |  after edit:               |
|  - findings.md ## Decisions|      |  - skip findings.md        |
|    entry (3-line shape)    |      |    (no active update may   |
|  - prd_drift.md row marked |      |     exist yet; git log is  |
|    Resolution = prd-update:|      |     the audit trail)       |
|    <letter>                |      |  - skip prd_drift.md mark  |
|  - tell user: resume update|      |  - tell user: run sync to  |
|                            |      |    scaffold milestone      |
+----------------------------+      +----------------------------+
```

Both modes share:

- The same 5 options (Tighten / Split / Demote / Exclude / Add) with identical wording.
- The same hard constraints (single-section minimum edit, no changelog markers, ≤2000 word ceiling, product-semantics-only).
- The same Drift check protocol (LSP + grep + double-source rule) on Tighten / Demote / Split — even in forward mode, the Tighten option must verify the new wording matches reality if the bullet already exists.

## 3. What `prd-update` does NOT do (still v0.5 boundaries)

- Does not rewrite multiple sections — that path stays `/super-manus:brainstorm`.
- Does not edit `prd/_index.md` — that path stays manual or `/super-manus:brainstorm` for big changes.
- Does not auto-trigger `/super-manus:sync` after a forward edit — user runs sync explicitly. Reason: user may want to batch multiple PRD edits before scaffolding a milestone.
- Does not write a `findings.md ## Decisions` entry in forward mode — there may be no active update folder. Audit trail is `git log -p prd/<module>.md`.
- Does not log forward edits to `prd_drift.md` — drift is by definition a divergence between PRD and reality, and a forward edit is the user moving PRD before reality changes; nothing is diverging.

## 4. Slash command surface (v0.6 — unchanged from v0.5 except prd-update positioning)

| Command | Role | Changed in v0.6? |
| --- | --- | --- |
| `/super-manus:start` | (no args) idempotent enable | no |
| `/super-manus:brainstorm` | 6-question Q&A, initial PRD | no |
| `/super-manus:reverse-prd` | one-shot scan of existing project | no |
| `/super-manus:sync <module>` | PRD-diff → Phases → scaffold update | no |
| `/super-manus:impl` | one phase via 3-agent pipeline | no |
| `/super-manus:impl-all` | loop all pending phases | no |
| **`/super-manus:prd-update <module>`** | **structured PRD edit (forward OR drift)** | **yes — repositioned** |
| `/super-manus:drive` | global next-step decider | no |
| `/super-manus:catchup` | re-inject context | no |
| `/super-manus:log` | manual session log | no |

`drive` is a candidate for a v0.6 minor update so it suggests `prd-update` for forward iteration too (currently it only suggests `prd-update` when drift is detected). That's a one-line change in `commands/drive.md`'s decision tree; deferred to follow-up.

## 5. Migration from v0.5

Pure additive. No path changes, no schema changes, no data migrations. v0.5 projects gain forward-iteration mode automatically the next time the user invokes `/super-manus:prd-update` on a module with no pending drift row.

`commands/prd-update.md` is the only file that changes meaning. Existing test `tests/test_command_prd_update_logic.sh` continues to pass — every assertion (5 options documented, no-changelog rule, 2000-word ceiling, brainstorm redirect, findings.md mention, progress.md no-edit, tech-vs-product distinction, Drift check protocol reference, LSP requirement, v0.4 path invariants) remains true under the broader framing.

## 6. Out of scope (v0.6)

- Repositioning `/super-manus:drive` to surface forward-iteration prompts (deferred — needs separate UX pass).
- A new `/super-manus:propose` or `/super-manus:add-feature` command — explicitly rejected; option A above.
- Auto-scaffolding a sync milestone after a forward `prd-update` (deferred — user explicit).
- Multi-section forward edits — still `/super-manus:brainstorm`.
- `prd/_index.md` edits via slash command — still manual.
- Everything still out of scope per [design-v0.5.md §10](design-v0.5.md): code review skill, retroactive e2e backfill, auto-promote phase test, multi-product monorepo, module rename, code-writer execution timeouts.

## 7. Plugin version

v0.6.0 (additive vs v0.5: prd-update reframing + docs sweep; no path migration). Plugin manifest at `.claude-plugin/plugin.json` is the canonical version source.
