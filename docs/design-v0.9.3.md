# super-manus v0.9.3 — deferred items log

This file is a forward-looking note, NOT a shipped release. Items recorded here are deferred design ideas surfaced during v0.9.x usage. Each entry stays here until either (a) it ships in a v0.9.x release (move to that release's design doc) or (b) it's rejected (record the rejection inline). Do NOT implement any item below without a separate user "ship it" directive.

## 1. probe-runtime listening-ports grayfilter

### Observation

`scripts/probe-runtime.sh` step 2 ("Listening ports") prints `lsof -iTCP -sTCP:LISTEN | head -40` raw. On a developer's macOS machine the output is dominated by system / IDE / chat-app processes that are guaranteed-not-project:

```
ControlCe (Control Center, ports 5000/7000)
rapportd (macOS handoff)
Code\x20H (VS Code helper)
Electron, language_ (IDE-internal)
WeChat (multiple ports)
privoxy, ss-local (proxy stacks)
com.docke (docker desktop manager, NOT the docker daemon's containers)
```

These dilute signal-to-noise to roughly 5-10 useful lines / 30-35 noise lines. The downstream architect agent has to filter mentally on every reverse-prd run.

### Why it's not in v0.9.0

The probe philosophy is "raw evidence → let the LLM judge." A blanket filter risks dropping legitimate processes for projects that genuinely use these binaries (e.g. an Electron-based app, a project that wraps `Code\x20H` Server). v0.9.0 chose to ship the raw dump and trust LLM filtering.

### Proposed v0.9.3 intervention (NOT yet ratified)

Add a **grayfilter** of known-false-positive process names. Inclusion criteria for the list: process name is high-confidence "macOS / chat / IDE noise" AND no plausible super-manus project would name a process this way.

Initial list (add only when corroborated by real false-positive observation):

```
ControlCe, rapportd, Code\x20H, Electron, language_, WeChat, privoxy, ss-local, com.docke
```

Implementation sketch (~5 lines):

```bash
# In probe-runtime.sh step 2, after lsof, before head -40:
GRAYFILTER='^(ControlCe|rapportd|Code\\x20H|Electron|language_|WeChat|privoxy|ss-local|com\.docke)'
listen_out=$(... | grep -vE "$GRAYFILTER" | head -40)
```

Plus a regression test (`tests/test_probe_runtime.sh` extension) that asserts the grayfilter is wired and the list is exhaustive against a synthetic lsof fixture.

### Open questions before ship

- **Scope.** macOS-only? Linux developer machines may have completely different noise (gnome-keyring, systemd-resolved, etc.).
- **Override.** Should the user be able to override the grayfilter via `.super-manus/agents.yml` (or a new config key) for projects where `Electron` is genuinely a project process?
- **Visibility.** When grayfilter drops lines, should the probe emit a one-line note ("filtered N grayfilter hits — set `probe.noise_filter = false` to disable") so users know it happened?

These three questions need to be answered before v0.9.3 implements. Until then: deferred.

### Status: shipped in v0.9.3 (alongside R1+R2+R3)

`scripts/probe-runtime.sh` step 2 ("Listening ports") gained a `LISTEN_NOISE_RE` grayfilter that drops the canonical macOS / Linux dev-machine noise processes:

```bash
LISTEN_NOISE_RE='^(ControlCe|rapportd|Code\\x20H|Electron|language_|WeChat|privoxy|ss-local|com\.docke)'
```

Filter is applied to both lsof and ss output paths. `tests/test_probe_runtime.sh` extended with assertion #10 — must define the grayfilter regex AND must include the canonical noise sources (ControlCe, rapportd, Electron, WeChat) so future contributors don't silently shrink the list. Real-world test on contributor's machine: lsof output went from 40 lines (~30 noise + ~10 signal) to 4 lines (4 real project python3.1 processes). Grayfilter is intentionally conservative — only entries that are 100% confidence "not a project process" land here.

---

## 2. PRD voice discipline — fix at the architect

### What the PRD is supposed to be

A PRD describes the **current actual state of the module** in a way that is **easy for a human to understand**. Two properties, both load-bearing:

1. **Faithful** — every bullet matches what the code actually does; no fabricated capabilities, no stale claims.
2. **Readable** — a PM, designer, support engineer, or end user can read the PRD without grepping the source code to figure out what each line means.

The first property is enforced by `reverse-prd-architect`'s existing cross-validation discipline (runtime probe + source grep + `(audit)` markers for unverified claims). v0.9.0 + v0.8.3 made it solid.

The second property is **not** enforced today, and v0.9.0 audit of teachagent `tutor-agent.md` shows the architect failing it.

### Observation

Real-world reverse-prd output (teachagent `tutor-agent.md` after dynamic-analysis pass) demonstrates the architect promoting impl detail into PM-voice prose:

- LLM tuning parameters in `## What users get`: `task_type=chinese_language`, `temperature=0.1`, `max_tokens=80`, `httpx.Timeout(0.3s)`
- Internal state struct field names: `active_agent`, `current_mode`, `target_agent`, `intent_decision={source:"manual_override"}`
- Verbatim wire schemas: `{"kind":"set_mode","mode":"chat|practice|lesson"}`
- Tuning constants as bullet content: "tail 6 条压成 ≤3 句 4 字段摘要"

The bullets are **faithful** (they cite real code). They are **not readable** by anyone who hasn't already read the source. The architect's existing "be specific, ground claims" pressure rewarded verbatim impl reproduction over translation to user observation.

### Three requirements (all in the same architect persona file)

These three changes ship together because they all answer the same goal: "make the PRD read like a user manual of the current system."

#### R1. Voice discipline

`agents/reverse-prd-architect.md` adds a `## PRD voice discipline` section. The discipline says:

**Each bullet describes user-observable behavior, not the code that produces it.** Engineering evidence — file paths, function names, struct fields, constants, tuning parameters — goes into the `Backed by:` citation that already trails every bullet. The bullet body itself reads as PM voice.

**Example capability bullets in this voice** (positive examples — what good looks like, the architect pattern-matches against these):

```
- **WebSocket 实时一节课** — 学生连上后服务端推渐进事件流 (say 1.2s /
  板书 1.8s 节奏), 模拟"老师渐进讲".
  Backed by: ws_server.py:619-624 (UTTERANCE_PACING_S 常量).

- **agent 意图自动切档** — 学生发消息后系统自动按意图选 sub-agent
  (300ms 超时上限). 低置信度或目标=当前不切档 (避免反复抖动), 学生不必
  手动 set_mode, 下一轮 sub-agent 自然接管.
  Backed by: intent_classifier.py:139-191 + supervisor.py:45-90.

- **PRACTICE 真题优先 + 难度自适应** — coach 出题先从题库召回, 命中真题
  带标准解析; 主题偏时退回 LLM 即兴编题. 难度按学生表现自适应升降
  (连错降一档, 答对升档).
  Backed by: agents/coach.py:76-120 + Qdrant rag_problems collection.
```

Each example shows: PM-voice user observation in bullet body, engineering evidence in `Backed by:` cite. Architect pattern-matches against these when drafting new bullets.

**Self-check the architect runs before committing each bullet**:

> Could a PM, customer success engineer, or support engineer who has not read the source code understand this bullet? If not, the impl detail belongs in the `Backed by:` cite line, not the bullet body.

#### R2. Use cases preamble inside `## What users get`

PRD as user manual benefits from "scenarios first, capabilities second" reading order. v0.9.3 adds a short use-cases preamble at the top of `## What users get`, BEFORE the capability bullets:

```markdown
## What users get

主要使用场景:
- **学生上一节正式课**: GREET → NEGOTIATE → PLAN → TEACH ⇄ PRACTICE → WRAPUP → PERSIST (15-30 分钟)
- **学生中途自由问答**: 不走剧本直接问"为什么 X = 5", server 走同款 RAG + actions JSON 输出
- **学生切换学习模式**: lesson / practice / chat 三档自由切, 切档时旧上下文压缩成短摘要喂新 sub-agent

实现这些场景的能力:

- **WebSocket 实时一节课** — ...
  Backed by: ws_server.py:619-624.

- **NEGOTIATE 选课卡片** — ...
  Backed by: ws_server.py:271-336.
```

**Format**: bold name + colon + one-line scenario in PM voice. 2–4 use cases typical. Each use case should map to ≥1 capability bullet below.

Architect uses PM-voice judgment for the scenario sentence — no fixed template. Skippable for tightly-scoped utility modules (pure CRUD API, passive metric exporter) where "the user uses it" doesn't decompose into multiple scenarios.

#### R3. User-facing flow Mermaid sub-section in `## How it connects`

Currently `## How it connects` shows an integration view (which module connects to which). For modules with **multi-step user flows** (e.g. tutor-agent's GREET → NEGOTIATE → PLAN → TEACH ⇄ PRACTICE → WRAPUP → PERSIST), add a separate "User-facing flow" Mermaid sub-section that shows the flow from the **user's perspective**, not the architecture:

```markdown
## How it connects

### User-facing flow

```mermaid
flowchart LR
  A[GREET] --> B[NEGOTIATE]
  B --> C[PLAN]
  C --> D[TEACH]
  D <--> E[PRACTICE]
  D --> F[WRAPUP]
  E --> F
  F --> G[PERSIST]
```

### Integration

(existing Mermaid showing web-student → ws_server → supervisor → tutor sub-graph etc.)
```

For modules with a multi-step user flow, add a rough Mermaid diagram showing the main path. Single-step modules (CRUD API, passive metric exporter) skip the sub-section — no empty headings.

Keep it rough. The goal is "user reads PRD and gets the main flow shape", NOT "exhaustive state machine with every conditional branch and edge case." If the architect is tempted to enumerate every state transition, that detail belongs in design-doc territory, not the user-manual PRD.

### How existing dirty PRDs get cleaned

`/super-manus:reverse-prd <module>` is already the regeneration path. Once the architect persona has the discipline, running reverse-prd on a dirty PRD produces a clean one. Same command, better output.

No separate `voice-pass` mode. No `--flag`. No lint regex. The architect IS the lint.

### Tests

Test extensions on existing `tests/test_agent_reverse_prd_architect.sh` (no new test files):

R1 (voice discipline) assertions:
- A `## PRD voice discipline` section heading exists in the persona file
- The discipline contains ≥2 positive example capability bullets
- The "self-check question" (PM / support engineer comprehension test) appears verbatim
- The principle "engineering evidence goes in `Backed by:` cite, not bullet body" appears verbatim

R2 (use cases preamble) assertions:
- The `## What users get` description in the persona file mentions "use cases" / "使用场景" / "用例" preamble
- Format guidance "bold name + colon + one-line scenario in PM voice" appears
- The "≥1 capability maps to each use case" mapping rule appears
- ≥2 positive use-case examples appear

R3 (user-facing flow) assertions:
- The `## How it connects` description in the persona file mentions "User-facing flow" sub-section
- ≥1 example Mermaid diagram appears
- The "skip if single-step / no empty headings" rule appears

Plus optionally extend `tests/test_template_prd_module.sh` if `templates/prd_module.md` is updated in lockstep (TBD per Open Question 2).

No new test files. No regex lint. The discipline is enforced by the LLM architect at draft time, not by a static checker.

### Decisions

**Template vs persona scoping (resolved)**:
- **R2 (use-case preamble) → template**. `templates/prd_module.md` gets a `主要使用场景:` placeholder block at the top of `## What users get`. Architects fill it; thin utility modules can leave it as `(none — single-scenario module)` or delete the placeholder entirely.
- **R3 (User-facing flow) → persona-only**. The Mermaid diagram is conditional on multi-step flow. No placeholder in `templates/prd_module.md`; architect adds the sub-section to `## How it connects` only when the module qualifies.

This split matches the visibility/conditionality tradeoff: R2 is universal-enough to pre-shape the template; R3 is conditional and would create empty headings on most modules.

### Final scope

The whole v0.9.3 milestone is now: one persona file edit (R1 + R2 + R3 instructions) + test extension on `test_agent_reverse_prd_architect.sh` (assertions for all three) + optional `templates/prd_module.md` update for R2 placeholder. Persona file grows from 334 lines to ~420 lines. No new commands, no new agents, no new modes. One small milestone, one phase plan, one phase to implement.

### Status: ratified — ready for implementation

User-confirmed shape across multiple discussion turns:
- "肯定是要 reverse-prd-architect 改" (R1 is needed)
- "我只要产出来的 prd 文件是符合系统当前模块实现逻辑的, 然后以一种便于人理解的方式描述当前实际状态就行" (the goal: faithful + readable user-manual)
- "用户视角流程图，这个要，用 mermaid 画" (R3)
- "用例/用户故事 要的 简单描述" (R2 confirmed)
- "Verify by 这个不要了" (no per-capability acceptance criteria)
- "prd直接写现在系统的情况就好了啊，为什么要前和后的情况" (drop ❌/✅ before-after, use positive examples only)
- "不需要特意禁用 As/I want/So that，直接让他用 pm 语气发挥就好了啊" (drop explicit ban; positive guidance only)
- "给个大概的流程图就好了，不需要太详细" (R3 stays rough; drop strict trigger rules)
- "R2 放模板 R3 只放 persona 可以" (template-vs-persona scoping resolved)

Spec is rules-light, examples-led: positive guidance + concrete examples, architect uses PM-voice judgment for the rest.

### Implementation milestone shape (when v0.9.3 ships)

A single milestone with one phase, touching:

1. `agents/reverse-prd-architect.md` — add `## PRD voice discipline` H2 section (R1) + extend `## What users get` heading description with use-case preamble guidance (R2 persona side) + extend `## How it connects` heading description with User-facing flow Mermaid sub-section guidance (R3).
2. `templates/prd_module.md` — add `主要使用场景:` placeholder block at the top of `## What users get` (R2 template side).
3. `tests/test_agent_reverse_prd_architect.sh` — assertions for R1 + R2 + R3 (per the Tests section above).
4. `tests/test_template_prd_module.sh` — assertion that the use-case preamble placeholder appears in the template.
5. `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — version bump 0.9.2 → 0.9.3.

Persona file 334 → ~420 lines. Template file gains ~5 lines for the preamble placeholder. No new commands, no new agents, no new modes.
