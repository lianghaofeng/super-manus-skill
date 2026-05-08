# super-manus

> 🌐 **语言**: [English](README.md) · **简体中文**

Claude Code 插件，做 **PRD 驱动、drift 感知** 的开发。状态在磁盘上，跨 `/clear` 和 `/compact` 存活。每个里程碑走一条 4-agent TDD 流水线（architect → test-writer → code-writer，加一个只读 reviewer 在三个 checkpoint 上），写实现的 agent 没权限改自己的测试，reviewer 的 verdict 驱动 re-spawn 循环直到 phase 收敛。一道 BLOCKING drift gate 拒绝在 PRD 与实际代码不一致时标记完工。

自给自足 —— 自带 TDD / verification / debugging 纪律 skill，不需要别的 workflow 插件。

## 安装

**推荐 —— marketplace：**

```
/plugin marketplace add https://github.com/lianghaofeng/super-manus-skill
/plugin install super-manus@super-manus-skill
```

后续更新通过 `/plugin marketplace update super-manus-skill`。

**本地 marketplace**（本地开发，或远程装失败时）：

```
/plugin marketplace add /path/to/super-manus
/plugin install super-manus@super-manus-skill
```

首次安装后重启 Claude Code session，让 hooks 和 slash 命令注册。

## 怎么用

日常循环很小：写一次 PRD，然后通过编辑 PRD bullet + 跑 phase 来迭代。每件事都是一条 slash 命令。

### 命令清单

| 命令 | 什么时候跑 | 做什么 |
|---|---|---|
| `/super-manus:start` | 项目开头一次 | 建 `docs/super-manus/prd/`、`impl/`、`roadmap.md`、`prd_drift.md`（`e2e/` 由 `impl-test-writer` 第一次写 e2e 时懒创建）。 |
| `/super-manus:brainstorm` | 新项目 | 6 题 PM 访谈 → 写 `prd/_index.md` + 各模块 `prd/<module>.md` 雏形。 |
| `/super-manus:reverse-prd` | 现有项目还没 PRD | 读代码（runtime-first 模块发现），写 `prd/_index.md`（含 ASCII 架构图）+ 各模块 stub。 |
| `/super-manus:prd-update <module>` | 加新能力 / 解决 drift | 对单份 `prd/<module>.md` 做 5 选 1 结构化编辑：**add / tighten / split / demote / exclude**。模式（前向迭代 vs drift 吸收）自动判定。 |
| `/super-manus:sync <module>` | PRD 改完之后 | 读 `git diff prd/<module>.md`，草拟 3-6 个候选 phase，scaffold 里程碑文件夹。 |
| `/super-manus:impl` | 跑一个 phase | 端到端跑一个 phase（architect → review → test-writer → review → code-writer → review → verify → close），然后停。Reviewer 在 3 个 checkpoint（pre-test / pre-code / pre-close）驱动 re-spawn 循环，每个 checkpoint 有独立 retry 预算。 |
| `/super-manus:impl-all` | 跑完整个里程碑 | 把当前 update 所有 pending phase 串起来跑，中间不停。每个 phase 仍走完整 4-agent 流水线 + 3 review checkpoint + drift check。 |
| `/super-manus:drive` | "下一步干啥？" | 读全状态，从 brainstorm / sync / prd-update / impl 中选一个，公布决定 + 理由，执行。 |
| `/super-manus:catchup` | 新 session | 把 PRD 总览 + 当前 update 的 task_plan 重新注入上下文。 |
| `/super-manus:log` | 手动 checkpoint | 立刻往当前 update 的 `progress.md` 追加一条 session log。 |

### `/super-manus:prd-update` 的 5 种编辑

PRD 编辑是结构化的，不能自由发挥。一次改一条 bullet。命令的提示按 a–e 字母顺序给出：

| 字母 | 选项 | 用在 | 效果 |
|---|---|---|---|
| **a** | Tighten | 表述太虚 | 用更锐利的用户可见语言 + 技术证据重写一条 bullet。 |
| **b** | Split | 一条 bullet 实际上是两个能力 | 把一条拆成两条，各自可独立审计。 |
| **c** | Demote | 之前承诺过头了 | 移到 `## Open questions`。 |
| **d** | Exclude | 不再在范围内 | 移到 `## Out of scope`。 |
| **e** | Add | 新加一个能力 | 往 `## What users get` 末尾追加一条 bullet。 |

任何编辑之后跑 `/super-manus:sync <module>` scaffold 下一个里程碑。

### 例 1 —— 全新项目，从头到尾

```bash
# 1. 启动
/super-manus:start
/super-manus:brainstorm
# 6 道 PM 风格的题，最后一题是模块拆分。
# 写 prd/_index.md + 各模块雏形，roadmap 标 not-started。

# 2. 你审 prd/api.md，把 ## What users get 写成实际想要的能力。
# PM 语气，最多 ~2000 词。

# 3. 为 api 模块切第一次里程碑
/super-manus:sync api
# 读 `git diff prd/api.md`，sync-planner agent 草拟 3-6 个 phase。
# 建 docs/super-manus/impl/api/2026-05-07-bootstrap/
# 含 task_plan.md（phase 表）+ findings.md + progress.md。
# 你审 phase，需要可改。

# 4. 把这次里程碑出清
/super-manus:impl-all
# 每个 pending phase：
#   - impl-architect 草拟 tasks/p<n>_impl.md
#   - impl-reviewer (pre-test)  → APPROVE / RETURN 给 architect
#   - impl-test-writer 提交红 phase + e2e 测试
#   - impl-reviewer (pre-code)  → APPROVE / RETURN 给 test-writer 或 architect
#   - impl-code-writer 写源码到测试翻绿
#   - impl-reviewer (pre-close) → APPROVE / RETURN 给任意上游 writer
#   - orchestrator hash check + 跑 ## Verification 命令
# 每个 checkpoint 最多容忍 2 次 RETURN；第 3 次 RETURN 升级到用户。
# 收尾时：drift gate 拒绝在 e2e 没覆盖每个触及的
# ## What users get 能力时把 roadmap 翻成 stable。
```

### 例 2 —— 中途加一个能力

你想到 API 还需要限流。先别去写代码 —— 先写 PRD。

```bash
# 1. 通过 PRD 把新能力浮出水面
/super-manus:prd-update api
# 选 "add"，回答 2-3 个关于新 bullet 的问题。
# 直接编辑 prd/api.md 的 ## What users get。
# 自动判定为前向迭代模式（没有 drift 行）。

# 2. 为新能力切一次里程碑
/super-manus:sync api
# 读 prd/api.md 的 diff，为"限流"草拟 phase。
# scaffold docs/super-manus/impl/api/2026-05-07-rate-limiting/。

# 3. 出清
/super-manus:impl-all
```

### 例 3 —— 代码偏离了 PRD

实现的过程中你顺手加了一个 PRD 里没承诺的 metrics 端点。drift checker 拦住你，往 `prd_drift.md` 追加一条 `pending` 行。两条路：

```bash
# 路 A —— 回退代码，跟 PRD 对齐。
git revert <commit>

# 路 B —— 让 PRD 跟过来（drift 吸收）。
/super-manus:prd-update api
# 自动判定为 drift 模式（api 模块有 pending 行）。
# 选 "add" 把 metrics 端点合法化。
# 同步往当前 findings.md 写一条 Decision；
# prd_drift.md 那条行的 Resolution 翻出 `pending`。
# 收尾 gate 解锁。
```

### 例 4 —— 接手一个现存项目

```bash
# 项目有代码，但还没 PRD。
/super-manus:start
/super-manus:reverse-prd
# orchestrator 跑 runtime-first 模块发现（compose / Makefile /
# apps / scripts），然后 spawn reverse-prd-architect（首席架构师 +
# 资深 PM 双 persona），它写 prd/_index.md（含必需的 ASCII 架构图）+
# 各模块 stub。

# 2. 审 (audit) 标记 —— 架构师拿不准的地方，你补全或纠正。
# 然后按模块：
/super-manus:sync <module>
/super-manus:impl-all
```

### 拿不准时

```bash
/super-manus:drive
# 读 PRD + roadmap + 当前 update + drift log，从
# brainstorm / sync / prd-update / impl 中选一个，
# 公布选什么 + 为什么，执行。
```

## 文件布局

super-manus 在使用它的项目里建出的磁盘布局：

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # 项目级，单一真相源
    │   ├── _index.md                           # 项目总览 + 模块清单 + 数据流（≤700 词）
    │   └── <module>.md                         # 每模块目标态（≤2000 词）
    ├── e2e/                                    # 常驻回归套，按 prd/ 镜像（懒创建 —— impl-test-writer 第一次写 e2e 时建）
    │   ├── _system/
    │   │   └── test_<scenario>.<ext>           # 来自 prd/_index.md ## Demo 的跨模块场景；自动发现，CI 跑
    │   └── <module>/
    │       └── test_<capability>.<ext>         # 来自 prd/<module>.md ## What users get 的能力测试；自动发现
    ├── roadmap.md                              # 项目级，模块状态表（自动管理）
    ├── prd_drift.md                            # 项目级，PRD ↔ 实现 drift 日志（append-only）
    └── impl/                                   # 每模块的里程碑时间序列
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # 时间戳唯一出现的地方
                ├── task_plan.md                # 这次迭代的 phase 索引（Goal + Phases 表）
                ├── findings.md                 # 这次迭代的决定 / 错误 / 数据点
                ├── progress.md                 # 这次迭代的 commit + session log（hook 管理）
                ├── tasks/
                │   └── p<n>_impl.md            # 每个 phase 的技术方案（懒加载）
                └── tests/
                    └── phase_p<n>_<verb>_<noun>.<ext>  # phase 测试，里程碑级，CI 不自动发现
```

**两轴**（不重叠）：

- `prd/<module>.md` 是模块**是什么** —— target state。`## What users get` 装 schema 草图 / endpoint 轮廓 / 屏幕流；`## Quality bar` 装用户可见的 NFR。
- `impl/<module>/<update>/task_plan.md` 是这个模块**一次迭代怎么做**的总览。
- `impl/<module>/<update>/tasks/p<n>_impl.md` 是**怎么做**的细节 —— DB 迁移、API 代码、每个 phase 的文件 diff。

**两层测试**（不可互换）：

- `e2e/` —— **常驻回归**。PRD 能力活多久，e2e 就活多久。pytest 默认 `test_*.py` glob 自动发现；jest/vitest 项目需要在 config 加 `testMatch: ['**/test_*.ts']`，因为它们默认的 `*.test.ts` glob **不会**匹配 `test_<capability>.ts` 这种命名。CI 每次 commit 跑。是里程碑收尾的关卡。
- `impl/<m>/<u>/tests/` —— **里程碑级 phase 测试**。跟着 update 一起提交，里程碑收尾后可归档。**CI 不自动发现** —— 通过显式路径调用。`phase_*` 前缀就是为了避开默认 test runner 的 glob。

**没有 active 状态文件**。Hooks 用 `docs/super-manus/impl/<module>/*/` 的 mtime 扫描自动 resolve 当前 active update。一个项目 = 一份 PRD，老版本里的"feature"抽象已经移除。

**PRD 里不留 changelog 标记**。PRD 是当前态快照，历史在 `git log` 和每个 update 的 `findings.md` 里。

## 改已有 PRD

PRD 存在以后，三条路径可以改它，作用粒度不同，互不重复：

| 改动范围 | 路径 | Source of truth |
|---|---|---|
| 一行 bullet（refine / split / demote / exclude / add） | `/super-manus:prd-update <module>` | 你的产品意图 |
| 一整页模块 PRD（代码漂移大，想刷新 9 个 section） | `/super-manus:reverse-prd <module>` | 当前源码 |
| 全工程 PRD（bootstrap，或者大改一轮） | `/super-manus:reverse-prd` | 当前源码 |

**简单规则**：`prd-update` 干外科手术式的产品意图编辑；`reverse-prd` 干源码驱动的批量重写。`prd-update` 拒绝跨 section 改写；`reverse-prd` 没有"改一行"入口。两者粒度不同。

**灰色地带——一个 section 里加 N 条 bullet**（比如想给多个模块批量补 Exposes/Consumes）：两边都不太顺手。`prd-update Add` × N 等于把 5 选项流程跑 N 遍；per-module `reverse-prd` 会重写所有 9 个 section。**手编通常最快**——[`templates/prd_module.md`](templates/prd_module.md) 里有精确格式。

### `prd-update` 怎么跑（两种模式，同一套选项）

同一套 5 选项，两种触发场景。命令读 `prd_drift.md` 自动判模式：

| `prd_drift.md` 里 `<module>` 有 pending 行吗？ | 模式 | 用在 |
|---|---|---|
| 没有 | **Forward iteration（前向迭代）** | 写代码 **之前** 加新能力 / 微调措辞 |
| 有 | **Drift absorption（drift 吸收）** | PRD 追上已经偏离的代码 |

调用端看不出区别 —— 同一条命令、同一套 5 选项。差别在副作用：

| 动作 | Forward | Drift |
|---|---|---|
| 编辑 `prd/<module>.md`（单 bullet、单 section） | ✅ | ✅ |
| 往当前 update 的 `findings.md ## Decisions` 写一条 3 行 Decision | — | ✅ |
| 翻 `prd_drift.md` 那行的 Resolution：`pending` → `prd-update: <a-e>` | — | ✅ |
| 动 `progress.md` | — （hook 管理） | — （hook 管理） |
| 收尾消息 | "跑 `/super-manus:sync <module>` scaffold 里程碑" | "Drift 行已 resolve，回去 resume update" |

**Tighten / Demote / Split** 三种动作在写之前会跑 [drift check protocol](skills/using-sm/SKILL.md)（LSP + grep 双源）核对受影响的 bullet —— 比如要"收紧"措辞，命令会先确认代码实际行为确实匹配新措辞，不只是用户记忆。**Add** 和 **Exclude** 跳过验证（Add 是新意图，Exclude 是去 scope）。

4 种情况它会拒绝并 redirect 你：

| 情况 | 建议 |
|---|---|
| 编辑跨过 `prd/<module>.md` 多个 section | 跑 `/super-manus:brainstorm`（替换式重写） |
| 偏离其实是 **技术决定**（比如"我们改用了 Redis 不是 Postgres"） | 不动 PRD —— 只在当前 update 的 `findings.md ## Decisions` 写一条 |
| PRD 跟代码已经对齐，没冲突 | 停，不要编一条编辑出来 |
| 编辑会把 `prd/<module>.md` 推过 2000 词 | `/super-manus:brainstorm` —— 这个模块已经撑不住一份 PRD 了 |

**技术决定**这条拒绝实际中最常见。PRD 是产品语义 —— "表 X 有字段 a/b/c" 这种 schema 草图可以；库名、文件路径、行号、代码标识符不行。如果一条"drift"实质上是"我们选了别的 DB"，那是 `tasks/p<n>_impl.md ## Approach` 的决定，不是 PRD 该动的地方。

`prd-update` 是「PRD 该动的时候你伸手用的工具」。下一节讲的是「**什么时候** PRD 可能该动」的那套系统 —— 也是阻止 agent 自己悄悄动 PRD 的机制。

## Drift 检测

super-manus 的核心铁律：**agent 永远不会静默更新 PRD**。PRD 和代码对不上时，分歧被写到 `prd_drift.md` 并暴露给你 —— 由你决定让代码回退还是让 PRD 跟过来。

### 什么算 drift

| 方向 | 例子 | 术语 |
|---|---|---|
| 代码多了 PRD 没承诺的能力 | 加了 `GET /metrics`，PRD 没承诺可观测性 | **over-shoot（超出）** |
| 代码少了 PRD 承诺的能力 | PRD 写「支持 SSO」，代码完全没做 | **under-shoot（欠缺）** |
| 代码违反 `## Quality bar` 条款 | PRD 写 p99 < 200ms，实测 5s | **质量违约** |
| 代码越过 `## Out of scope` 红线 | PRD 排除移动端，但加了 React Native 入口 | **越界** |

流水线违规也会写到 `prd_drift.md`，行为完全一致：`code-writer modified tests for phase p<n>`（防作弊哈希不一致）、`test-writer touched non-test files`、`missing e2e coverage for capability <c>`、`e2e for capability <c> is red`。这些行也算进 gate 的 `pending` 总数，并且和 PRD-代码偏离一样，会拦住 roadmap 翻 `stable`。

### 什么时候跑

**不是后台守护进程**，是命令执行路径上主动跑的，6 个入口（来源是 [skills/using-sm/SKILL.md §4 Per-command application](skills/using-sm/SKILL.md)）：

| 触发时机 | 对比的内容 |
|---|---|
| `/super-manus:reverse-prd` | 推断出的 PRD 声明 vs 现有代码（初次 bootstrap） |
| `/super-manus:sync <module>` | 新里程碑的意图 vs 该模块当前 PRD |
| `/super-manus:prd-update`（Tighten / Demote / Split） | 收紧/降级/拆分后的 bullet vs 现有代码（写之前的验证） |
| `/super-manus:impl`（进入 phase 时） | phase 的 `## Objective` vs PRD `## What users get` / `## Quality bar` / `## Out of scope` |
| `/super-manus:drive` | PRD + roadmap + 最近 commit 消息提示（轻量 pre-action sweep） |
| End-of-update gate（3 pass） | Pass 1 refresh from commits / Pass 2 e2e 覆盖 / Pass 3 `pending` 必须为 0 |

### 检测机制

协议在 [skills/using-sm/SKILL.md §4](skills/using-sm/SKILL.md)，用两种工具回答不同问题：

- **LSP**（`workspace_symbols`、`document_symbols`、`find_references`）—— 结构性事实：PRD 声称的 symbol 在索引过的代码里到底存不存在？
- **grep + Read** —— 文本信号：TODO 注释、route 路径、配置文件、license 条款，凡是 LSP 索引不到的。

**双源规则（double-source rule）**：一条 drift 结论必须 LSP 和 grep **在两者都适用时**都同意（有些推断目标 —— Quality bar、Risks、产品 intent —— 本质上 grep- 或 Read-only，LSP 用不上）。单源结论会变成 `(audit)` 标记 —— 可以 inline 写在 `prd/<module>.md` 任何位置，或者归到 `## Open questions` —— **不进 prd_drift.md**。每次检查的预算：≤10 次 LSP 调用 + ≤30 次 grep/Read 调用；超预算 → 停下报告，不做穷举式扫描。

LSP 不可用时（冷项目、多语言仓库、缺工具链）→ grep-only 模式，所有结论都带 `(audit)` 标。

### 检测到 drift 之后

```
检测到
   ↓
往 prd_drift.md append 一行（Resolution = pending）
   ↓
agent 停下，给你三条 resolve 路径：
   1. /super-manus:prd-update <m>      —— 让 PRD 跟过来（drift 模式翻 Resolution → prd-update: <a-e>）
   2. git revert <commit> + 编辑该行    —— 让代码退回 PRD；手动改 Resolution = reverted，并在 findings.md 写一句 why
   3. 补缺失的 e2e + 重跑 gate          —— 对 Pass 2 "missing/red e2e" 行，补 e2e 让它绿，gate 自己清
   ↓
你决定。agent 绝不静默改 PRD。
   ↓
收尾 gate 在该模块还有 pending 行时
拒绝把 roadmap 翻成 stable
```

`prd_drift.md` 是 **行级别 append-only** —— 只有 Resolution 单元格可变；行本身永不删除、永不重排。这套机制和"防止写实现的 agent 给自己测试放水"是同一个底层原则 —— 没有静默覆盖，每一处分歧都留底。

## 自给自足的执行纪律

super-manus 不依赖任何别的 workflow 插件。执行层是内置的：

- **`impl-reviewer` agent + 3 个 review checkpoint（v0.7）** —— 只读 agent，在 impl 流水线的三个点上：
  - **`pre-test`**（architect 之后、test-writer 之前）—— 核对 plan 的声明对照真实数据（对每个声称的输入跑 `head -1`、`(audit)` 标记必须 resolve、每个声明的输入在 `## Verification` 里都要有 smoke）。
  - **`pre-code`**（test-writer 之后、code-writer 之前）—— 核对 fixture 用真实数据样本（不是从 architect 的 plan 文本派生的 inline dict）、覆盖所有声明输入、测试如预期是红的、测试通过项目配置的 type-check（无配置则跳过）。
  - **`pre-close`**（code-writer 之后、verification 之前）—— 核对实现匹配 `## Approach`、改的文件是 `## Files touched` 的子集、无安全 smell。如果 code-writer 报 stuck（"tests un-passable"），reviewer 诊断到底是测试、plan 还是代码出问题。
  
  Verdict：**APPROVE** / **RETURN_TO_<writer>** / **ESCALATE_TO_USER**。RETURN 可以指向任意上游 writer——`pre-close` 看到失败的 fixture 错可以 RETURN_TO_TEST_WRITER，看到 plan 写错可以 RETURN_TO_ARCHITECT。Orchestrator 串联——重 spawn 目标 writer + 所有下游阶段，新 test 提交后刷新 hash baseline，再回到原 review。**每个 checkpoint 的预算：最多 2 次 RETURN；第 3 次 RETURN 升级到用户**，附完整反馈历史。Reviewer 的 **工具栏只读**（无 `Write`，无 `Edit`）—— 防作弊边界完整保留。

- **`tdd-in-phases`** —— `/super-manus:impl` 进入一个 phase 时，test-writer 在 code-writer 之前 spawn（不可商量）。Phase 测试 + e2e 测试以红色提交；code-writer 把它们翻绿，并且禁止改测试。三条独立机制堵住"写实现的 agent 给自己测试放水"：
  - **时间** —— 测试在 code-writer spawn 之前已经在 git 里了。
  - **写权限** —— code-writer 的 persona 禁止改测试；orchestrator 哈希测试文件（在 `pre-code` review APPROVE 之后）、code-writer 跑完后再哈希一次比对，被改就中止。
  - **Persona** —— test-writer 把测试锚定在 PRD 的 `## What users get` / `## Quality bar` / `## Risks` 加上 `_index.md ## Demo`（跨模块场景 → `e2e/_system/`），把 `## Approach` 当成"众多合法实现之一"。
- **`verification-before-phase-close`** —— phase Status 翻 `closed` 之前，`tasks/p<n>_impl.md ## Verification` 里的每条命令必须返回 0。`## Verification` 至少包含 (1) 本 phase 的 phase 测试路径命令，(2) 一条用户可见的 smoke 命令。
- **`systematic-debugging-in-phase`** —— verify 失败时按 checklist 走（重读 Approach、重读失败测试、对 diff 二分查找、写一条回归测试，再 fix）。同一类错误三次 → 上报。

如果你之前把 super-manus 和 `obra/superpowers` 一起装，现在不再需要了。v0.5+ 把 superpowers 里真正合 PRD-led loop 的三块（TDD / verification / 系统化调试）吸收进来；剩下的要么和 super-manus 重叠，要么正交。

## 不做的事

主动留在范围外：

- 模块改名命令（手动：改文件夹名 + 编辑 `prd/_index.md`）
- 单 super-manus 文件夹下的多产品 monorepo 支持（用多个 super-manus-enabled 子目录）
- 自动把 phase 测试升级成 e2e（手动：移文件 + 改名）
- 给 v0.4 老项目回填 e2e（自己补，或者等以后有 phase 触及那个能力时由 test-writer 顺手补）
- 多 harness 编排 / PR 创建 / 合并集成
- 测试框架 / runner —— super-manus 调用你项目已有的（`pytest`、`npm test`、`cargo test`、`go test`、`Makefile` 目标），不强加一个

## 更新历史

`.claude-plugin/plugin.json` 是版本号的唯一真相源。每个版本下面链了对应的 design 文档。

### v0.7.3 —— 当前

修了 `impl-architect`：之前 agent 会对 `${CLAUDE_PLUGIN_ROOT}/templates/phase_plan.md` 直接 `Edit`（in-place 替换占位符），触发 Claude Code 对 plugin cache 下文件的 sensitive-file 权限提示，整个 phase 被卡住。原因是 seeding 流程（Bash + `sed` 输出到 `${update_dir}/`）被埋在 `## Idempotency` 末尾，容易被跳过。

重构 `agents/impl-architect.md ## Deliverable`，加了一段不可协商的 **Write barrier**（`Edit`/`Write` 只能落在 `${update_dir}/` 下；`${CLAUDE_PLUGIN_ROOT}/` 下的模板是 READ-ONLY），并把流程拆成有序三步，把 Bash+sed seeding 钉为唯一一条"从模板生成目标文件"的路径。`tests/test_agent_impl_architect.sh` 加了三条断言把这条 barrier 锁死。纯 agent-guidance 修复，不动 PRD schema、运行时 API，也不需要迁移。

### v0.7.2

`/super-manus:reverse-prd` 加了两个易用性改进：

- **Per-module 模式**：传一个已有的 `<module>` 名字进去，只刷新 `prd/<module>.md`，不动 `_index.md`、`roadmap.md`、也不动其它模块。适用于"某个模块代码改了想把它的 PRD 同步到最新（包括 v0.7.1 的 Exposes/Consumes 块）"，不需要重扫整个工程。刷完后 orchestrator 跑一次 **cascade scan**——grep 其它 `prd/*.md` 看哪些模块在 `## How it connects` 里提到了目标模块——然后打印一个 follow-up 列表，告诉用户哪些模块的"How it connects"可能已陈旧。**不会** silently regenerate 那些模块；用户自己决定要不要单独刷或手动改。新模块的 bootstrap 仍然需要整工程跑。
- **Soft-abort 二次确认**（取代 v0.7.0 的 hard-abort）：当用来判断是否覆盖的那一段（whole-project 看 `_index.md ## Problem`；per-module 看 `prd/<module>.md ## Why this exists`）已经写了真实人工内容时，orchestrator 不再直接拒绝，而是通过 `AskUserQuestion` 弹出确认（明确列出会覆盖什么）。之前那种"先备份、清回模板再跑"的麻烦没了——确认机制保留了"绝不静默覆盖"的安全属性，但摩擦小得多。

`agents/reverse-prd-architect.md` 加了两个新输入（`scope`、`target_module`）；`scope=single-module` 时只写 `prd/<target_module>.md`，并被明文禁止动 `_index.md` 或其它模块文件。详见 `docs/design-v0.7.md` §12。

### v0.7.1

PRD 模板小幅锐化，借鉴自一次 formal-PRD 框架讨论：

- **`prd/<module>.md ## How it connects`** 顶部加 `Exposes:` / `Consumes:` 语义前导块，原有 Upstream/Downstream/Third-party + edge list 紧随其后。条目是 PM 口吻的能力名词（"order placement"、"credit-score lookup"），不是 endpoint 路径。让模块的"对外契约面"在 PRD 里直接可见，模块拆分决策只看 PRD 就能审。
- **`prd/_index.md ## Data flow overview`** 的 edge list backup 强制 `(for: <capability>)` 标注：`<A> --<protocol>--> <B> [path/topic] (for: <capability>)`。`<capability>` 用的是和各模块 Exposes/Consumes 相同的词汇表。跨模块边从只带协议变成带语义。

两处都是**纯追加**——没有 heading 重命名，MODULE–DIAGRAM INVARIANT 保留，已有 PRD 不需要迁移（重跑 `/super-manus:reverse-prd` 自动填，或手动补）。`agents/reverse-prd-architect.md` 同步更新派生规则（Exposes 来自本模块 `## What users get`；Consumes 来自上游模块 `## What users get`；`(for: ...)` 来自被消费的 capability bullet）。完整 rationale 见 `docs/design-v0.7.md` §11。

### v0.7.0

加了 **`impl-reviewer` agent**，在 `/super-manus:impl` 和 `/super-manus:impl-all` 内部三个 checkpoint（`pre-test` / `pre-code` / `pre-close`）跑。工具栏只读（无 `Write`、无 `Edit`），驱动 re-spawn 循环，每个 checkpoint 最多容忍 2 次 RETURN，第 3 次 RETURN 带完整历史升级到用户。Verdict：`APPROVE` / `RETURN_TO_<writer>` / `ESCALATE_TO_USER`。RETURN 可指任意上游 writer——`pre-close` reviewer 可以 RETURN_TO_TEST_WRITER 如果失败测试的 fixture 错了，或者 RETURN_TO_ARCHITECT 如果 plan 在 impl 阶段才暴露写错。**防作弊保留**：hash baseline 在 `pre-code` review APPROVE 之后才建立，绝不更早。

为什么：2026 年 5 月一个 dogfood 案例（多源 parser）暴露了 v0.6 的 3-agent 线性信任链的两个结构缺陷——plan-time 编造（architect 列字段名但没 `head -1` 验证；5/6 源在生产里静默 drop）和 test-side 死路（测试写错时 code-writer 改不动测试，v0.6 的逃生通道概念上有但机制没接通）。Reviewer 通过注入外部真实信号（`head -1` 真数据、项目配置的 type-check、code-vs-plan diff 核对）打破这条信任链，并给循环一个干净的 RETURN-with-feedback 路径，不破坏 hash baseline。

详见 [docs/design-v0.7.md](docs/design-v0.7.md)。Plugin manifest 0.7.0；相对 v0.6 纯 additive（无路径迁移、无 PRD schema 改动、无测试 fixture 改动）。

### v0.6.1

修了 `impl-architect`：phase 测试现在强制声明在 `${update_dir}/tests/phase_p<n>_*.<ext>`，而不是借用项目原有测试套（`apps/<m>/tests/`、`docs/super-manus/e2e/`）。`tests/test_agent_impl_architect.sh` 加了配套断言。纯 agent guidance + template 修复，无路径迁移。

### v0.6.0 —— prd-update 双模式

`/super-manus:prd-update` 同时覆盖前向迭代（写代码前加新 bullet）和 drift 吸收（解决 `prd_drift.md` 的 pending 行）两种模式，模式从 `prd_drift.md` 状态自动判定。配套一次 docs sweep。v0.5 的所有内容沿用。详见 [docs/design-v0.6.md](docs/design-v0.6.md)。

### v0.5 —— 自给自足执行纪律 + e2e 回归

加了 **3-agent `/super-manus:impl` 流水线**（architect → test-writer → code-writer，test-writer 和 code-writer 之间有时间 / 写权限 / persona 三条边界）和 **常驻 e2e 回归套**（位于 `docs/super-manus/e2e/`，按 PRD 的 module/_index 结构镜像）。End-of-update drift gate 多了一个 **Pass 2 —— e2e 覆盖检查**：本次 update 触及的每个 `## What users get` 能力都需要有一个绿色的 `e2e/<module>/test_<capability>.<ext>`，否则 roadmap 不能翻 `stable`（Pass 3 仍然是 `pending == 0` 的总闸）。三个执行纪律 skill（`tdd-in-phases`、`verification-before-phase-close`、`systematic-debugging-in-phase`）随插件一起出。新增 `/super-manus:impl-all`。详见 [docs/design-v0.5.md](docs/design-v0.5.md)（已弃用）。

### v0.4 —— 项目级全局 PRD

两轴模型 —— 模块 × 里程碑 —— 替换 v0.2/v0.3 的 per-feature 文件夹。PRD 在 `docs/super-manus/prd/`（一个项目 = 一份 PRD）。实现按模块按里程碑放在 `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/`。Drift gate（PRD ↔ 实现对齐）变成 BLOCKING。`.super-manus/active` 指针文件移除 —— hooks 用 mtime 扫描 resolve。详见 [docs/design-v0.4.md](docs/design-v0.4.md)（已弃用）。

### v0.2 / v0.1 —— 早期版本

[docs/design-v0.2.md](docs/design-v0.2.md) 和 [docs/design-v0.1.md](docs/design-v0.1.md)。Per-feature 文件夹布局，`.super-manus/active` 指针文件。已弃用，保留作历史参考。
