# super-manus

> 🌐 **语言**: [English](README.md) · **简体中文**

Claude Code 插件，做 **PRD 驱动、drift 感知** 的开发。状态在磁盘上，跨 `/clear` 和 `/compact` 存活。每个里程碑走一条 3-agent TDD 流水线（architect → test-writer → code-writer），写实现的 agent 没权限改自己的测试。一道 BLOCKING drift gate 拒绝在 PRD 与实际代码不一致时标记完工。

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
| `/super-manus:start` | 项目开头一次 | 建 `docs/super-manus/{prd,impl,e2e}/`、`roadmap.md`、`prd_drift.md`。 |
| `/super-manus:brainstorm` | 新项目 | 6 题 PM 访谈 → 写 `prd/_index.md` + 各模块 `prd/<module>.md` 雏形。 |
| `/super-manus:reverse-prd` | 现有项目还没 PRD | 读代码（runtime-first 模块发现），写 `prd/_index.md`（含 ASCII 架构图）+ 各模块 stub。 |
| `/super-manus:prd-update <module>` | 加新能力 / 解决 drift | 对单份 `prd/<module>.md` 做 5 选 1 结构化编辑：**add / tighten / split / demote / exclude**。模式（前向迭代 vs drift 吸收）自动判定。 |
| `/super-manus:sync <module>` | PRD 改完之后 | 读 `git diff prd/<module>.md`，草拟 3-6 个候选 phase，scaffold 里程碑文件夹。 |
| `/super-manus:impl` | 跑一个 phase | 端到端跑一个 phase（architect → test-writer → code-writer → verify → close），然后停。 |
| `/super-manus:impl-all` | 跑完整个里程碑 | 把当前 update 所有 pending phase 串起来跑，中间不停。每个 phase 仍走完整流水线 + drift check。 |
| `/super-manus:drive` | "下一步干啥？" | 读全状态，从 brainstorm / sync / prd-update / impl 中选一个，公布决定 + 理由，执行。 |
| `/super-manus:catchup` | 新 session | 把 PRD 总览 + 当前 update 的 task_plan 重新注入上下文。 |
| `/super-manus:log` | 手动 checkpoint | 立刻往当前 update 的 `progress.md` 追加一条 session log。 |

### `/super-manus:prd-update` 的 5 种编辑

PRD 编辑是结构化的，不能自由发挥。一次改一条 bullet：

| 选项 | 用在 | 效果 |
|---|---|---|
| **add** | 新加一个能力 | 往 `## What users get` 末尾追加一条 bullet。 |
| **tighten** | 表述太虚 | 用更锐利的用户可见语言 + 技术证据重写一条 bullet。 |
| **split** | 一条 bullet 实际上是两个能力 | 把一条拆成两条，各自可独立审计。 |
| **demote** | 之前承诺过头了 | 移到 `## Open questions`。 |
| **exclude** | 不再在范围内 | 移到 `## Out of scope`。 |

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
#   - impl-test-writer 提交红 phase + e2e 测试
#   - impl-code-writer 写源码到测试翻绿
#   - orchestrator 跑 ## Verification 命令
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
    ├── e2e/                                    # 常驻回归套，按 prd/ 镜像
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

- `e2e/` —— **常驻回归**。PRD 能力活多久，e2e 就活多久。你项目原有的 test runner 自动发现（pytest `test_*.py`、jest `*.test.ts`）。CI 每次 commit 跑。是里程碑收尾的关卡。
- `impl/<m>/<u>/tests/` —— **里程碑级 phase 测试**。跟着 update 一起提交，里程碑收尾后可归档。**CI 不自动发现** —— 通过显式路径调用。`phase_*` 前缀就是为了避开默认 test runner 的 glob。

**没有 active 状态文件**。Hooks 用 `docs/super-manus/impl/<module>/*/` 的 mtime 扫描自动 resolve 当前 active update。一个项目 = 一份 PRD，老版本里的"feature"抽象已经移除。

**PRD 里不留 changelog 标记**。PRD 是当前态快照，历史在 `git log` 和每个 update 的 `findings.md` 里。

## `prd-update` 怎么跑（两种模式，同一套选项）

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

### 什么时候跑

**不是后台守护进程**，是命令执行路径上主动跑的，5 个入口：

| 触发时机 | 对比的内容 |
|---|---|
| `/super-manus:sync <module>` | 新里程碑的意图 vs 该模块当前 PRD |
| `/super-manus:impl`（进入 phase 时） | phase 的 `## Objective` vs PRD `## What users get` / `## Quality bar` / `## Out of scope` |
| `/super-manus:impl`（每次 commit 之后） | commit 消息 + diff 暗示的能力 vs PRD |
| `/super-manus:drive` | roadmap + PRD + 代码三方对照 |
| End-of-update gate（3 pass） | refresh from commits / e2e 覆盖检查 / pending == 0 必须成立 |

### 检测机制

协议在 [skills/using-sm/SKILL.md §4](skills/using-sm/SKILL.md)，用两种工具回答不同问题：

- **LSP**（`workspace_symbols`、`document_symbols`、`find_references`）—— 结构性事实：PRD 声称的 symbol 在索引过的代码里到底存不存在？
- **grep + Read** —— 文本信号：TODO 注释、route 路径、配置文件、license 条款，凡是 LSP 索引不到的。

**双源规则（double-source rule）**：一条 drift 结论必须 LSP 和 grep 都同意；单源结论会变成 PRD `## Open questions` 里的 `(audit)` 标记，**不进 prd_drift.md**。每次检查的预算：≤10 次 LSP 调用 + ≤30 次 grep/Read 调用；超预算 → 停下报告，不做穷举式扫描。

LSP 不可用时（冷项目、多语言仓库、缺工具链）→ grep-only 模式，所有结论都带 `(audit)` 标。

### 检测到 drift 之后

```
检测到
   ↓
往 prd_drift.md append 一行（Resolution = pending）
   ↓
agent 停下，给你两条路：
   1. git revert <commit>           —— 让代码退回 PRD
   2. /super-manus:prd-update <m>   —— 让 PRD 跟过来
   ↓
你决定。agent 绝不静默改 PRD。
   ↓
收尾 gate 在该模块还有 pending 行时
拒绝把 roadmap 翻成 stable
```

`prd_drift.md` 是 **append-only**。Resolution 翻出 `pending` 只有两条路径：通过 `/super-manus:prd-update`（drift 模式），或者下次 drift check 发现冲突已经不存在了（比如 `git revert` 之后）。这套机制和"防止写实现的 agent 给自己测试放水"是同一个底层原则 —— 没有静默覆盖，每一处分歧都留底。

## 自给自足的执行纪律

super-manus 不依赖任何别的 workflow 插件。执行层是内置的：

- **`tdd-in-phases`** —— `/super-manus:impl` 进入一个 phase 时，test-writer 在 code-writer 之前 spawn（不可商量）。Phase 测试 + e2e 测试以红色提交；code-writer 把它们翻绿，并且禁止改测试。三条独立机制堵住"写实现的 agent 给自己测试放水"：
  - **时间** —— 测试在 code-writer spawn 之前已经在 git 里了。
  - **写权限** —— code-writer 的 persona 禁止改测试；orchestrator 哈希前后比对，被改就中止。
  - **Persona** —— test-writer 把测试锚定在 PRD 的 `## What users get` / `## Quality bar` / `## Risks`，把 `## Approach` 当成"众多合法实现之一"。
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

### v0.6.x —— 当前

`/super-manus:prd-update` 同时覆盖前向迭代（写代码前加新 bullet）和 drift 吸收（解决 `prd_drift.md` 的 pending 行）两种模式，自动判定。配套一次 docs sweep，外加修了一个 `impl-architect` 把 phase 测试声明在 `${update_dir}/tests/`（而不是借用项目原有测试套）的强制约束。v0.5 的所有内容沿用。详见 [docs/design-v0.6.md](docs/design-v0.6.md)。

### v0.5 —— 自给自足执行纪律 + e2e 回归

加了 **3-agent `/super-manus:impl` 流水线**（architect → test-writer → code-writer，agent 之间有时间 / 写权限 / persona 三条边界）和 **常驻 e2e 回归套**（位于 `docs/super-manus/e2e/`，按 PRD 的 module/_index 结构镜像）。End-of-update drift gate 多了一个 Pass 3 —— e2e 覆盖检查：本次 update 触及的每个 `## What users get` 能力都需要有一个绿色的 `e2e/<module>/test_<capability>.<ext>`，否则 roadmap 不能翻 `stable`。三个执行纪律 skill（`tdd-in-phases`、`verification-before-phase-close`、`systematic-debugging-in-phase`）随插件一起出。新增 `/super-manus:impl-all`。详见 [docs/design-v0.5.md](docs/design-v0.5.md)（已弃用）。

### v0.4 —— 项目级全局 PRD

两轴模型 —— 模块 × 里程碑 —— 替换 v0.2/v0.3 的 per-feature 文件夹。PRD 在 `docs/super-manus/prd/`（一个项目 = 一份 PRD）。实现按模块按里程碑放在 `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/`。Drift gate（PRD ↔ 实现对齐）变成 BLOCKING。`.super-manus/active` 指针文件移除 —— hooks 用 mtime 扫描 resolve。详见 [docs/design-v0.4.md](docs/design-v0.4.md)（已弃用）。

### v0.2 / v0.1 —— 早期版本

[docs/design-v0.2.md](docs/design-v0.2.md) 和 [docs/design-v0.1.md](docs/design-v0.1.md)。Per-feature 文件夹布局，`.super-manus/active` 指针文件。已弃用，保留作历史参考。
