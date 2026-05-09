# reverse-prd v0.8.0: Dynamic probe + smart budget

Replaces `reverse-prd-dynamic-probe-and-budget.md` (草案). This is the
implementation-ready version.

## 0. 用户的真实痛点

> "项目改了很多遍，有很多死代码。"

纯静态分析读源码，看不出哪些是活的、哪些是被遗忘的——它把所有 import 链都当成有效连线，把
所有 `apps/<X>/` 目录都当成正在运行的模块。结果：PRD 里塞着早就废弃的模块，捏造出已经断开
的边，让用户在审核时一头雾水。

**核心解法不是"再多读几个文件"，而是"问运行时它现在在做什么"——一个端口在监听就比一万行
源码可信。**

## 1. 设计原则

1. **静态是底线**——动态探测失败、被跳过、或被用户拒绝，PRD 照样产出。
2. **动态是交叉校验**——能摸到运行时事实就用来给静态结论加权，标记一致 / 冲突 / 单源。
3. **被动只读**——不向业务接口注流量，不写数据库，不调用任何会改变状态的命令。
4. **唯一例外：`docker compose up -d`**——但必须用 `AskUserQuestion` 显式征得用户同意。
5. **跨平台**——darwin 是一等公民（用户主力平台），Linux 同时支持。`ss` 和 `lsof`
   都试，先到先用。
6. **正交于 v0.7.2 confirmation gate**——动态探测在 confirmation 通过后、Stage 1 之后、
   spawn agent 之前发生。

## 2. 架构改动总览

```
┌─────────────────────────────────────────────────────────────────┐
│  /super-manus:reverse-prd  (commands/reverse-prd.md)            │
│                                                                 │
│   1. Setup + mode resolution + confirmation gate  (现状)        │
│   2. Stage 1 — Module discovery (declarative)     (现状)        │
│ ▶ 3. Stage 2 — Runtime probe                       (新增)       │
│      a. Bash: scripts/probe-runtime.sh → runtime_facts          │
│      b. 解析 runtime_facts:                                     │
│         • compose 文件存在 ∧ 服务全停 → AskUserQuestion          │
│         • 用户同意 → docker compose up -d (60s 超时)             │
│           成功后重跑 probe-runtime.sh                           │
│         • 用户拒绝 / 超时 / 无 compose → 跳过                    │
│   4. Spawn reverse-prd-architect with runtime_facts (新增 input)│
│   5. Verify post-conditions + roadmap update      (现状)        │
└─────────────────────────────────────────────────────────────────┘

   ↓ Bash invocation

┌─────────────────────────────────────────────────────────────────┐
│  scripts/probe-runtime.sh  (新文件)                             │
│                                                                 │
│   只读探测，全部命令带超时；任何子命令失败都吞掉，整体 exit 0    │
│                                                                 │
│   输出 (stdout, 带固定 ===/--- 标头的纯文本，agent 直接读):     │
│     === RUNTIME PROBE (timestamp) ===                          │
│     --- Running processes ---       (ps aux 过滤)               │
│     --- Listening ports ---         (lsof / ss)                 │
│     --- Docker containers ---       (docker ps)                 │
│     --- Compose services ---        (docker compose ps)         │
│     --- OpenAPI contracts ---       (curl /openapi.json …)      │
│     --- Git activity ---            (deleted / cold / hot files)│
│     --- Notes ---                   (platform / 跳过原因)       │
└─────────────────────────────────────────────────────────────────┘

   ↓ runtime_facts string passed via spawning prompt

┌─────────────────────────────────────────────────────────────────┐
│  agents/reverse-prd-architect.md  (改动)                        │
│                                                                 │
│   • 新输入: runtime_facts                                       │
│   • 新章节: ## Cross-validation with runtime_facts              │
│   • Tool budget 改: 10 + 5×N + 10  (N = 模块数), 上限 60         │
│   • (audit) 子类型: runtime-unverified / runtime-only / source-runtime-conflict        │
└─────────────────────────────────────────────────────────────────┘
```

## 3. `scripts/probe-runtime.sh` 详细规格

### 3.1 调用约定

```bash
scripts/probe-runtime.sh [--project-root <path>] [--ports <p1,p2,...>]
```

- `--project-root` 默认 `$PWD`。用于 git 命令的 `-C` 和 ps 过滤的根路径匹配。
- `--ports` 可选。orchestrator 从 Stage 1 解析的 compose 文件里提取出服务声明端口
  列表（如 `8000,8001,5173`），传进来用于 OpenAPI 探测的目标。如果没传，脚本就遍历
  `--- Listening ports ---` 里捕获到的所有 localhost TCP 端口。
- 始终输出 `=== RUNTIME PROBE …` 开头的报告到 stdout，stderr 静默（脚本内部 `2>/dev/null`）。
- **始终 exit 0**，即使所有子探测都失败。orchestrator 不依赖退出码判断状态。
- 总耗时硬上限 **30 秒**（每个子探测 3-5s 超时累加）。

### 3.2 探测项

| # | 名称 | 命令（macOS / Linux） | 超时 | 失败处理 |
|---|---|---|---|---|
| 1 | Running processes | `ps -eo pid,command \| grep -E '<patterns>' \| grep -F "$ROOT"` | n/a | 输出 `(none)` |
| 2 | Listening ports | macOS: `lsof -iTCP -sTCP:LISTEN -P -n` ; Linux: `ss -tlnp` 优先，回退 lsof | 3s | 输出 `(probe unavailable)` |
| 3 | Docker containers | `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'` | 3s | `docker not installed` / `daemon not running` |
| 4 | Compose services | 检测 `docker-compose.yml` 等 6 个常见路径 → `docker compose -f <file> ps --format json` | 5s | `no compose file` / `compose CLI missing` |
| 5 | OpenAPI contracts | 对每个目标端口尝试 `/openapi.json` `/openapi.yaml` `/docs/openapi.json` `/swagger.json` `/api-docs` | 3s/请求 | 跳过该端口 |
| 6 | Git activity | `git -C $ROOT log --since='6 months ago' --diff-filter=D --name-only --pretty=format:` 等 | 5s | `not a git repo` |

#### 3.2.1 Process pattern

匹配下列关键字之一（不区分大小写）：`uvicorn`, `gunicorn`, `hypercorn`, `fastapi`,
`flask`, `node `, `next`, `vite`, `npm run`, `pnpm`, `yarn`, `cargo run`, `go run`,
`python -m`, `python3 -m`, `rails`, `puma`, `streamlit`。

**且**进程命令行包含 `--project-root` 路径片段（避免抓到无关项目的进程）。

#### 3.2.2 OpenAPI 抓取

```bash
curl -sS -o "$tmp" -w '%{http_code}' --max-time 3 \
     "http://localhost:${port}${path}" 2>/dev/null
```

只有 200 状态码且 body 看起来像 JSON/YAML（首字符是 `{` / `o` / `s`）才计入。
输出格式：

```
http://localhost:8001/openapi.json (3142 bytes, 23 paths)
  GET  /api/sessions
  POST /api/sessions
  GET  /api/sessions/{id}
  ... (truncated, total 23)
```

最多列出每个端点 15 行；超过则 `...(truncated, total <N>)`。Body 不入报告
（保护上下文长度）。

#### 3.2.3 Git activity

输出三个子块（每块最多 10 行）：

```
Deleted in last 50 commits:
  apps/old-prototype/main.py  (deleted 2026-03-12)
  ...

Cold files (no edit since 2025-11-09, top 10 by size):
  apps/legacy-batch/runner.py  (last touched 2025-08-04)
  ...

Hot files (most edits in last 6 months, top 10):
  apps/api/routes.py  (47 edits)
  ...
```

cold/hot 只统计代码扩展名（`.py .ts .tsx .js .jsx .go .rs .rb .java`），跳过
`node_modules/ vendor/ dist/ build/ .venv/`。

### 3.3 输出契约

orchestrator 和 agent 都依赖固定的标头格式。任何标头改名 = 破坏契约。固定标头：

```
=== RUNTIME PROBE (probe-runtime.sh @ <ISO timestamp>) ===
--- Running processes ---
--- Listening ports ---
--- Docker containers ---
--- Compose services ---
--- OpenAPI contracts ---
--- Git activity ---
--- Notes ---
```

`--- Notes ---` 内容包含：
```
Platform: darwin | linux | other
Total duration: <X>s
Skipped probes: <list with one-line reason each>
```

### 3.4 安全护栏

- 所有外部命令必须有超时（`curl --max-time`, `timeout 3 ss`, etc.）。
- `set -uo pipefail` 但**不**用 `set -e`——子探测失败不能中止整个脚本。
- 不调用任何 mutating 命令（`docker run`, `docker compose up`, `psql -c "..."`, etc.）。
  `docker compose up -d` 是 orchestrator 的责任，不在脚本里。
- 不读 secrets 文件（`.env`, `secrets/*`）。

## 4. `commands/reverse-prd.md` 改动

### 4.1 新增章节：`## Stage 2 — Runtime probe`

位置：紧挨着 `## Discover modules — runtime-first` 之后，`## Hand off content
generation to the architect subagent` 之前。

```markdown
## Stage 2 — Runtime probe (whole-project + per-module modes)

This stage gathers passive runtime evidence to cross-validate the static module
list. The architect will treat the result as a second source alongside source
reading.

### Run the probe

Bash: `${CLAUDE_PLUGIN_ROOT}/scripts/probe-runtime.sh --project-root <project_root>
--ports <comma-separated ports from Stage 1.1 compose file, or empty>`

Capture stdout into a variable `runtime_facts` (or write to a tempfile and read
back — either works as long as the full text reaches the agent prompt).

### Interpret + Docker startup gate

Inspect `runtime_facts`:

1. If the `--- Compose services ---` block lists a compose file but shows zero
   services in `running` state, AND the `--- Docker containers ---` block is
   `(none)` — services are stopped:

   Use `AskUserQuestion`:
   - **Question**: "Found `<compose file>` but no services are running. Reverse-prd
     is more accurate when services are live (it can curl `/openapi.json`, see real
     ports, etc.). Start them with `docker compose up -d` now?"
   - **Options**:
     - "Start services (~30–60s wait)" — orchestrator runs `docker compose -f
       <file> up -d`, then polls `docker compose -f <file> ps` every 5s up to
       60s waiting for all services to be `running` or `healthy`. On
       success, **re-run probe-runtime.sh** and overwrite `runtime_facts`. On
       timeout, keep partial probe and append `(audit — startup timeout)`
       note to runtime_facts via the orchestrator.
     - "Skip dynamic probing" — proceed with current `runtime_facts` (which
       documents services as not running).

2. Otherwise (services already running, or no compose file, or apps run
   host-native) — proceed without prompting.

### Pass to the architect

Add `runtime_facts` to the spawning prompt as the 9th input (after `lsp_available`).
```

### 4.2 在 spawning prompt skeleton 里加一行

```
> - lsp_available: `<true|false>`
> - runtime_facts: |
>     <full multi-line probe output here>
```

### 4.3 测试断言（`test_command_reverse_prd_logic.sh` 加的项）

- 必须出现 `Stage 2` / `Runtime probe` 字样
- 必须引用 `scripts/probe-runtime.sh` 路径
- 必须出现 `runtime_facts` input 名
- 必须用 `AskUserQuestion` 处理 docker 启动征询（不能静默执行 `docker compose up`）
- 必须有 60s 超时上限的描述

## 5. `agents/reverse-prd-architect.md` 改动

### 5.1 Inputs 加一项

```markdown
- `runtime_facts` — multi-section text from `scripts/probe-runtime.sh` covering
  live processes, listening ports, docker containers, compose status, OpenAPI
  contracts, git activity, and notes. May be partial or marked `(none)` if
  probes failed or were skipped. Use as cross-validation evidence per the
  Cross-validation protocol below. **Do NOT** invent capabilities purely from
  runtime — runtime is for cross-checking the static reading, not for inventing
  new content (the only exception is OpenAPI rule 3c below).
```

### 5.2 新章节：`## Cross-validation with runtime_facts`

位置：`## Granularity default` 之前。

```markdown
## Cross-validation with runtime_facts

The orchestrator gathered passive runtime evidence and passed it as
`runtime_facts`. Use it as a second source alongside static reading. Apply these
rules in order; if `runtime_facts` is empty or every section says `(none)` /
`(probe unavailable)`, skip this entire protocol — bare `(audit)` policy
remains.

### 1. Module liveness

When listing a module in `_index.md ## Modules`, check for any of:

- A line in `--- Running processes ---` whose command-line matches the module's
  entry (e.g. `uvicorn parent_api.app:app` for module `parent-api`)
- A line in `--- Docker containers ---` whose name maps to the module
- A line in `--- Listening ports ---` on a port the module declares in compose

If **none** match AND the probe was actually run (`--- Notes ---` shows
`Total duration: > 0s`) AND the probe was not "skipped" for this module,
append `(audit — runtime-unverified)` to that module's `## Modules` row description.

### 2. Dead-code suspicion

If a module's primary entry file (the one identified for `## What users get`
priority 1 — Dockerfile CMD target / `[project.scripts]` entry / launch target)
appears in `--- Git activity --- Cold files` (no edit in 6 months) AND no
running process for it, add a one-line `## Open questions` entry on that
module's PRD:

> Entry `<file>` has no recent activity (`<last touched date>`) and no running
> process — confirm this module still ships, or move to `## Out of scope`.

### 3. Capability cross-check via OpenAPI

If `--- OpenAPI contracts ---` lists a `localhost:<port>` URL whose port maps
to one of this module's compose-declared ports:

- (3a) **Match** — a route appears in both static reading AND OpenAPI: no
  marker, high confidence.
- (3b) **Static-only** — route declared in source (e.g. via
  `@router.get("/foo")`) but missing from OpenAPI: keep the static-derived
  bullet but append `(audit — source-runtime-conflict: declared in source, not exposed at
  runtime)`. Common cause: route disabled by feature flag, or behind an
  upstream filter.
- (3c) **Runtime-only** — route in OpenAPI but no static evidence: add it
  to `## What users get` with `(audit — runtime-only: exposed at runtime, source
  not located)`. Common cause: dynamically registered routes, decorator-based
  plugins.

### 4. Edge confidence

For each edge in `_index.md ## Data flow overview`:

- If both endpoints have running processes / containers AND the URL in static
  env vars matches an actual listening port from `--- Listening ports ---`:
  high confidence, no marker.
- If neither endpoint is running: edge stays at static confidence (no extra
  marker; do NOT add `(audit — runtime-unverified)` to every edge — it'd flood
  diagrams).

### 5. (audit) subtype rules

Three new subtypes, all optional and additive on top of bare `(audit)`:

- `(audit — runtime-unverified)` — static evidence exists, runtime probe couldn't
  confirm. Used in rule 1.
- `(audit — runtime-only)` — runtime evidence exists, static source not located.
  Used in rule 3c.
- `(audit — source-runtime-conflict)` — static and runtime disagree. Used in rule 3b.

Bare `(audit)` and `(audit — <freeform>)` remain valid for cases not covered
by these subtypes.
```

### 5.3 替换 Tool budget 章节

把 `## Source reading — Drift check protocol` 末尾的 `Budget: ≤10 LSP calls
+ ≤30 grep / Read calls total` 那行删掉，新增独立章节 `## Tool budget`
（紧挨着 `## Source reading — Drift check protocol` 之后）：

```markdown
## Tool budget

Total budget: `10 + 5 × N + 10` calls, where N = number of modules in
`module_list`. Hard cap **60** regardless of N.

| N modules | Budget |
|-----------|--------|
| 1         | 25     |
| 3         | 35     |
| 6         | 50     |
| 8         | 60 (cap) |
| 12        | 60 (cap) |

Spend high-density tools first:

- `runtime_facts` — already in your input, **free** to read; biggest signal-
  per-byte source you have.
- LSP `workspace_symbols` — 1 call → project-wide map.
- `Glob` — 1 call → confirm/exclude file existence.
- `Read` of small entry file (<200 lines) — Dockerfile CMD target,
  `[project.scripts]` entry, top-level route file.
- `Grep` with precise symbol on bounded directory.
- LSP `find-references` — ≤3 per module.
- `Read` of large files (>1000 lines) or broad-keyword `Grep` — only if
  budget remains.

When ~80% of budget is spent, stop opening new modules to deeply read.
Finalize what you have. Mark unverifiable claims `(audit)` rather than
skipping the section.

This replaces the v0.7.0 flat `≤10 LSP + ≤30 grep / Read` cap.
```

### 5.4 测试断言（`test_agent_reverse_prd_architect.sh` 加的项）

- 必须文档化 `runtime_facts` input
- 必须有 `## Cross-validation with runtime_facts` 章节
- 必须出现三个 (audit) 子类型字样：`runtime-unverified`、`runtime-only`、`source-runtime-conflict`
- 必须出现 `10 + 5` 公式或 `5 × N` 字样
- 必须出现 `60` 上限字样
- 旧的 `≤10 LSP` / `≤30 grep` 硬数字断言改成"必须有 budget 章节"

## 6. 测试方案

### 6.1 新增 `tests/test_probe_runtime.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
S=scripts/probe-runtime.sh
[ -f "$S" ] || { echo "FAIL: missing $S"; exit 1; }
[ -x "$S" ] || { echo "FAIL: $S not executable"; exit 1; }

# Syntax
bash -n "$S" || { echo "FAIL: bash syntax error"; exit 1; }

# Smoke run in tmpdir (no project, nothing running) — must exit 0 and produce headers
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
out=$("$S" --project-root "$TMP" 2>/dev/null) || { echo "FAIL: non-zero exit"; exit 1; }

# Required header contract — orchestrator + agent depend on these
for h in \
  "=== RUNTIME PROBE" \
  "--- Running processes ---" \
  "--- Listening ports ---" \
  "--- Docker containers ---" \
  "--- Compose services ---" \
  "--- OpenAPI contracts ---" \
  "--- Git activity ---" \
  "--- Notes ---" \
; do
  echo "$out" | grep -qF "$h" || { echo "FAIL: missing header '$h'"; exit 1; }
done

# Notes section must declare platform and total duration
echo "$out" | grep -qE "^Platform: " || { echo "FAIL: Notes must declare Platform"; exit 1; }
echo "$out" | grep -qE "^Total duration: " || { echo "FAIL: Notes must declare Total duration"; exit 1; }

# Must always exit 0 even when invoked on non-git, no-services dir
"$S" --project-root "$TMP" >/dev/null 2>&1
[ $? -eq 0 ] || { echo "FAIL: must exit 0 in degraded environment"; exit 1; }

# Must NOT invoke any mutating commands — read script source, no docker run/up,
# no psql exec, no git commit
grep -E '\bdocker (run|compose up|start|restart)\b' "$S" && { echo "FAIL: probe must not invoke mutating docker commands"; exit 1; } || true
grep -E '\bpsql\b' "$S" && { echo "FAIL: probe must not invoke psql in v1"; exit 1; } || true
grep -E '\bgit (commit|push|reset|checkout)\b' "$S" && { echo "FAIL: probe must not invoke mutating git commands"; exit 1; } || true

echo OK
```

### 6.2 更新 `tests/test_agent_reverse_prd_architect.sh`

新增断言（追加到既有断言后；不删除任何现有断言）：

```bash
# v0.8.0: runtime_facts input
grep -qF "runtime_facts" "$F" || { echo "FAIL: agent must document the runtime_facts input"; exit 1; }

# v0.8.0: cross-validation protocol
grep -qF "## Cross-validation with runtime_facts" "$F" || { echo "FAIL: agent must declare the Cross-validation protocol"; exit 1; }

# v0.8.0: three (audit) subtypes
grep -qF "runtime-unverified" "$F" || { echo "FAIL: must declare (audit — runtime-unverified) subtype"; exit 1; }
grep -qF "runtime-only"   "$F" || { echo "FAIL: must declare (audit — runtime-only) subtype"; exit 1; }
grep -qF "source-runtime-conflict"   "$F" || { echo "FAIL: must declare (audit — source-runtime-conflict) subtype"; exit 1; }

# v0.8.0: tool budget formula 10 + 5×N + 10, cap 60
grep -qE "10 \+ 5" "$F" || { echo "FAIL: must declare budget formula 10 + 5 × N + 10"; exit 1; }
grep -qE "\b60\b" "$F" || { echo "FAIL: must declare hard cap 60"; exit 1; }
grep -qF "## Tool budget" "$F" || { echo "FAIL: must have a ## Tool budget section"; exit 1; }
```

旧的 `grep -qiE "≤10|10 LSP|budget"` 断言保留——`10 + 5 × N + 10` 也包含 `10`，
通过；且独立 `## Tool budget` 章节里 `budget` 字样依然在。

### 6.3 更新 `tests/test_command_reverse_prd_logic.sh`

```bash
# v0.8.0: Stage 2 runtime probe
grep -qiE "Stage 2|Runtime probe" "$F" || { echo "FAIL: must document Stage 2 — Runtime probe"; exit 1; }
grep -qF "scripts/probe-runtime.sh" "$F" || { echo "FAIL: must invoke scripts/probe-runtime.sh"; exit 1; }
grep -qF "runtime_facts" "$F" || { echo "FAIL: must pass runtime_facts to the architect"; exit 1; }

# v0.8.0: Docker startup gate must be user-confirmed (AskUserQuestion), not silent
grep -qE "AskUserQuestion.*compose|compose.*AskUserQuestion|Start services" "$F" \
  || { echo "FAIL: docker compose up gating must use AskUserQuestion (not silent execution)"; exit 1; }
grep -qE "60s|60-second|60 seconds|60s timeout" "$F" || { echo "FAIL: docker startup must declare a 60s timeout cap"; exit 1; }
```

### 6.4 不动的测试

`test_layout_v05.sh`、`test_template_*`、所有其他 agent / hook 测试都不受影响。

## 7. 改动清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `scripts/probe-runtime.sh` | 新增 | 探针脚本（被动只读，cross-platform） |
| `tests/test_probe_runtime.sh` | 新增 | 探针脚本测试 |
| `agents/reverse-prd-architect.md` | 改 | 加 input + Cross-validation 章节 + Tool budget 重写 + audit 子类型 |
| `commands/reverse-prd.md` | 改 | 加 Stage 2 章节 + AskUserQuestion 网关 + spawn prompt 多一行 |
| `tests/test_agent_reverse_prd_architect.sh` | 改 | 新增 v0.8.0 断言 |
| `tests/test_command_reverse_prd_logic.sh` | 改 | 新增 v0.8.0 断言 |

**不动：** `commands/{brainstorm,impl,impl-all,prd-update,sync,...}.md`、所有
`templates/`、所有 `skills/`、`hooks/`、`scripts/{sm-start,sm-update,refresh-outstanding}.sh`。

## 8. 不做的事（v1 范围之外）

- Postgres `\dt` 探测——密码 / schema / 用户配置太多边界；信号弱、错误率高。Phase 2 再说。
- 主动注流量（`/health`、业务端点）——副作用风险，违反 v1 被动原则。
- 启动 host-native 进程（`uvicorn`、`npm run dev` 等）——只 docker compose 一种。
- Trace 收集 / metrics 抓取——超出"运行时事实"范畴。
- 跨 update 的 runtime cache——每次重新探测；30s 上限可以接受。
- "用户启动服务后补做交叉比对" 续作命令——若需要，单独命令 `/super-manus:reverse-prd-recheck`。

## 9. 推出后的预期收益

针对用户痛点（"项目改了很多遍，有很多死代码"）：

1. **死代码模块** → 静态发现 + 没有 running process / 是 cold file → `(audit — runtime-unverified)`
   + Open question 提醒 → 用户审核时一眼看出。
2. **断开的边** → 静态推断的依赖端口没人在监听 → 边的可信度自然降低（虽然 v1 没在边上加
   marker，但 module liveness 已经间接表明）。
3. **真实 capability** → curl `/openapi.json` 拿到的路由 = ground truth → 静态漏读的
   动态注册路由能补回；静态有但运行时没暴露的会被标 `source-runtime-conflict`。

非死代码场景（首次运行的新项目）：runtime_facts 提供的也是有价值的交叉证据，没有副作用。

## 10. 实现顺序

1. 写 `scripts/probe-runtime.sh` + 让它自洽地跑通空目录场景。
2. 写 `tests/test_probe_runtime.sh`。
3. 更新 `agents/reverse-prd-architect.md`。
4. 更新 `commands/reverse-prd.md`。
5. 更新两个测试文件加 v0.8.0 断言。
6. `bash tests/run-all.sh` 全绿。
