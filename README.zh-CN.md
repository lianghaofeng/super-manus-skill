# super-manus

> 🌐 **语言**: [English](README.md) · **简体中文**

*PRD 驱动、drift 感知的 Claude Code 开发流。在 `/clear` 后存活，从 git 历史生成开发可读的进度日志。自给自足 —— 自带 TDD / verification / debugging 纪律和一条防 "agent 给自己的测试放水" 的 3-agent impl 流水线。*

## 是什么

**super-manus** 是 Claude Code 插件，做 PRD 驱动、drift 感知的开发。它管四件事：(1) 磁盘上一份项目级文件夹，存 PRD、roadmap、drift 日志、每次里程碑迭代的实现状态；(2) hooks 在你 commit 时把它们保持同步；(3) 一条 3-agent `/super-manus:impl` 流水线（architect → test-writer → code-writer），三者之间有明确的时间 / 写权限 / persona 边界；(4) 一份位于 `docs/super-manus/e2e/` 的常驻 e2e 回归测试套，按 PRD 模块结构镜像，并且作为里程碑收尾的关卡。

## 为什么

单次 LLM 编码在 `/clear` 或 `/compact` 后什么都没留下。计划优先工具（Manus 风格的文件级状态、[OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)）能保住状态，但不强制代码与 spec 对齐。一个 agent 同时写测试和实现，天然有动机：测试放水、照着 impl plan 镜像写测试、看完 impl 再回头调期望。v0.5 super-manus 三件一起做：跨 session 持久化状态、BLOCKING 的 drift gate（PRD 与实际代码不一致就拒绝标记里程碑完工）、3-agent impl 流水线（用时间 + 写权限 + persona 三条边界堵掉常见作弊路径）。

它自带一份精简的执行纪律层（按 phase 的 TDD、phase 收尾前强制 verification、phase 卡住时的系统化调试），可以独立运行 —— 不再需要别的 workflow 插件。

## v0.5 —— 自给自足的执行纪律 + e2e 回归测试套

v0.5 完全保留 v0.4 的项目级 PRD 布局，在它之上加了两件事：一条堵掉 "agent 给自己测试放水" 作弊路径的 3-agent `/super-manus:impl` 流水线，外加一份位于 `docs/super-manus/e2e/` 的常驻 e2e 回归测试套（按 PRD 的 module / _index 结构镜像）。

**3-agent /super-manus:impl 流水线**。每个 phase 串行跑三个 agent，agent 之间有显式的信任边界：

1. **`impl-architect`** —— 草拟 `tasks/p<n>_impl.md`（Objective / Approach / Files touched / Verification）。不写代码，不写测试。从 v0.4 沿用，没改。
2. **`impl-test-writer`** —— 写 phase 测试到 `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.<ext>`（每个 phase 必写）；当本 phase **完成** 一个 `## What users get` 能力，写/扩 e2e 测试到 `docs/super-manus/e2e/<module>/test_<capability>.<ext>`；当本 phase 完成一个 `prd/_index.md ## Demo` 跨模块场景，写到 `docs/super-manus/e2e/_system/test_<scenario>.<ext>`。提交时所有新写测试都是红的。Persona 纪律：测试锚定在 PRD spec，不照 `## Approach` 镜像。
3. **`impl-code-writer`** —— 按 `## Approach` + `## Files touched` 写实现，迭代直到 phase 测试 + 本 phase 触及的 e2e 测试全绿。**没有权限改 `tests/` 或 `e2e/`**（persona 显式禁止）；orchestrator 在它跑前后哈希所有测试文件，发现被改 → 中止 phase。

3-agent 拆分只为一件事：**防止写实现的 agent 给自己的测试放水**。三条独立机制把这事堵死：

- **时间边界** —— test-writer 在 code-writer 启动 *之前* 就 commit 了红测试。等 code-writer 上场时，测试已经在 git 里了，没有"未来 impl"可镜像。
- **写权限边界** —— code-writer 的 persona 禁止改测试；orchestrator 哈希 + 比对，被改就中止。
- **Persona 纪律** —— test-writer 显式锚定在 `prd/<module>.md ## What users get` / `## Quality bar` / `## Risks`，把 `## Approach` 当成"众多合法实现之一"，拒绝镜像它。

读权限是开放的 —— 两个新 agent 都能读所有东西。防作弊靠 时间 + 写权限 + persona，不靠藏文件。

**两层测试维护**。test-writer 同时维护两套：

- **Phase 测试**，路径 `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>` —— 里程碑级的证据，**CI 不会自动发现**。生命周期：跟着 milestone update folder 一起存在。
- **e2e 测试**，路径 `docs/super-manus/e2e/<module>/test_<capability>.<ext>` 和 `docs/super-manus/e2e/_system/test_<scenario>.<ext>` —— 镜像 PRD 结构的常驻回归套，**默认 test runner 自动发现**（pytest `test_*.py`、jest `*.test.ts`）。生命周期：能力在 PRD 里活多久，e2e 就活多久。

CI 每次 commit 跑 e2e 套；phase 测试只在 `/super-manus:impl` 跑 phase 时通过显式路径调用。

**两条 impl 命令：**

- `/super-manus:impl` —— 默认（DOGFOOD）。跑一个 phase 端到端（architect → test-writer → code-writer → verify → close），然后停。如果那是最后一个 pending phase，跑 end-of-update drift gate。**适合**：还没完全信任 plan、想一次 session 一个 phase 的自然 git history、要在 phase 之间切换上下文。
- `/super-manus:impl-all` —— POWER MODE。把当前 update 的所有 pending phase 串起来跑，中间不停。每个 phase 仍然走完整的 3-agent 流水线 + drift check；唯一区别是 phase 之间不暂停。中途任何中止（Ctrl-C、agent 报错、检测到 drift、检测到 tamper、gate 失败）后磁盘状态等价于 `/super-manus:impl` 跑了对应次数，回退到 `/super-manus:impl` 是安全的。

**End-of-update drift gate 增加 Pass 3 —— e2e 覆盖检查**。本次 update 的 commit 触及的每个 `## What users get` 能力，`e2e/<module>/test_<capability>.<ext>` 必须存在 AND 通过。缺失或红 → `prd_drift.md` 加 `pending` 行，BLOCKING roadmap 翻 `stable`。

完整设计见 [docs/design-v0.5.md](docs/design-v0.5.md)。[docs/design-v0.4.md](docs/design-v0.4.md)（已弃用）和 [docs/design-v0.2.md](docs/design-v0.2.md)（已弃用）保留作历史参考。

### v0.4 —— 项目级全局 PRD（仍然在用）

v0.5 完全保留 v0.4 的不变量。v0.4 的布局 —— 项目级 PRD + 模块 × 里程碑两轴模型 —— 没变：

- **PRD 是项目级的**（`docs/super-manus/prd/`），一个模块一份文件（db / api / frontend / ...）。每份模块 PRD 允许在 `## What users get` 段写 schema 草图、接口轮廓、UX 流 —— PM 给工程的细节量级 —— 上限 ~2000 词。下面有 9 个稳定标题（Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions）。项目级 `prd/_index.md` 在 Problem / Demo / Must / Not doing / Modules / Data flow overview 之上，多了 Audience + Success metrics 两段。
- **实现按模块按里程碑**：每次"里程碑迭代"是 `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/` 下的一个文件夹，含四件套（`task_plan.md`、`findings.md`、`progress.md`、`tasks/p<n>_impl.md`），v0.5 多了一个 `tests/` 子文件夹放 phase 测试。老 update 是不可变历史记录，最新的是 active。**时间戳只出现在这里**。
- **PRD ↔ 实现对齐是强制的**：当 intent 与 PRD 偏离，agent 停下，写到 `prd_drift.md`，问用户：回退实现，还是跑 `/super-manus:prd-update <module>`。PRD 永不静默更新。
- **没有 active 状态文件**。v0.2/v0.3 的 `.super-manus/active` 指针没了。Hooks 用 `docs/super-manus/impl/<module>/*/` 的 mtime 扫描自动 resolve 当前 active update。"feature" 这个抽象消失了 —— 一个项目 = 一份 PRD。

## 安装

**推荐方式 —— 加 marketplace，再 `/plugin` 装：**

```
/plugin marketplace add https://github.com/lianghaofeng/super-manus-skill
/plugin install super-manus@super-manus-skill
```

后续更新通过 `/plugin marketplace update super-manus-skill`。

**本地 marketplace（本地开发，或远程装失败时）：**

```
/plugin marketplace add /path/to/super-manus
/plugin install super-manus@super-manus-skill
```

指向本仓库的本地 clone —— `marketplace.json` 在 `.claude-plugin/marketplace.json`，从同一个 checkout 解析插件。

首次安装后，重启 Claude Code session 让 hooks 和 slash 命令注册。

## 快速开始（v0.4）

```
/super-manus:start                        # 幂等地建 docs/super-manus/{prd,impl}/、
                                          # roadmap.md、prd_drift.md（无参数）
/super-manus:brainstorm                   # 6 个问题（最后一题 = 模块拆分）。写
                                          # docs/super-manus/prd/_index.md + 各模块
                                          # prd/<module>.md 雏形，roadmap 标 not-started
... 用户审 prd/<module>.md，把 ## What users get 写实 ...
/super-manus:sync <module>                # 读 `git diff prd/<module>.md` 检测你刚加的
                                          # 新能力，spawn sync-planner agent 草拟 3-6 个
                                          # 候选 Phase（带 (audit) 标），scaffold
                                          # docs/super-manus/impl/<module>/<date>-<name>/
                                          # 含四件套 + planner 的 Phases；roadmap 翻 iterating
... 用户审 task_plan.md 的 Phases（planner 草拟，不是空白）...
/super-manus:impl                         # 自动找下一个 pending phase，跑 drift check，
                                          # spawn impl-architect agent 草拟 tasks/p<n>_impl.md，
                                          # 然后写代码 + commit。完工时：BLOCKING drift gate
                                          # 拒绝在 prd_drift.md 还有该模块 pending 行时
                                          # 标 update 完工。
git commit -m "..."                       # post-commit hook 提示 agent 把 commit 写进当前
                                          # update 的 progress.md
/clear                                    # 安全 —— 状态在磁盘上
... 下次 session ...                       # SessionStart hook 注入 prd/_index.md + 当前
                                          # update 的 task_plan
```

PRD 和实现偏离时：

```
/super-manus:prd-update <module>          # 对单份模块 PRD 做外科级编辑（5 选 1：
                                          # tighten / split / demote / exclude / add）。
                                          # 不留 changelog 标记；当前 update 的 findings.md
                                          # 同步加一条 Decision。
/super-manus:sync <module>                # PRD 改了 —— 为该模块 scaffold 新的 update folder
```

不知道下一步干啥时，用全局开关：

```
/super-manus:drive                        # 读全部状态，从 brainstorm / sync / prd-update /
                                          # impl 中选一个，公布决定 + 理由，执行
```

对一个还没 PRD 的现存项目：

```
/super-manus:reverse-prd                  # 一次性：orchestrator 跑 runtime-first 模块发现
                                          # （compose / Makefile / apps / scripts），然后
                                          # spawn reverse-prd-architect agent（首席架构师 +
                                          # 资深 PM 双 persona），它写 docs/super-manus/prd/
                                          # _index.md（含必需的 ASCII 架构图）+ 各模块 stub。
                                          # 之后审 (audit) 标记，再按模块跑 sync。
```

**两轴模型**（不重叠）：

- `prd/<module>.md` 是模块**是什么**（target state）。`## What users get` 装 schema 草图 / endpoint 轮廓 / 屏幕流；`## Quality bar` 装用户可见的 NFR。
- `impl/<module>/<update>/task_plan.md` 是这个模块**一次迭代怎么做**的总览。
- `impl/<module>/<update>/tasks/p<n>_impl.md` 是**怎么做**的细节 —— DB 迁移、API 代码、每个 phase 的文件 diff。

v0.4 下 PRD 编辑有两条路：

- **常规迭代**：直接编辑 `prd/<module>.md`（加一条 `## What users get` bullet，收紧 `## Quality bar`），然后跑 `/super-manus:sync <module>` —— sync v2 读 git diff，自动为新能力草拟 Phases。
- **外科级吸收 drift**：实现已经偏离，且你想让 PRD 跟过来（而不是回退代码），用 `/super-manus:prd-update <module>` 做单段最小编辑（5 选 1：tighten / split / demote / exclude / add）。当前 update 的 `findings.md` 同步加一条 Decision；`prd_drift.md` 行的 Resolution 翻出 `pending`，解锁 end-of-update drift gate。

PRD 与实现的偏离一律写到 `prd_drift.md`（append-only），由用户解决。PRD 文件每模块 ≤2000 词、`_index.md` ≤700 词。**不留 changelog 标记** —— PRD 是当前态快照，历史在 `git log` 和 `findings.md`。

**Session log 节奏**未变 —— Stop hook 通过 `SUPER_MANUS_LOG_EVERY_N_TURNS`（默认 5）和 `SUPER_MANUS_LOG_MODE`（`both` / `turns` / `commit` / `off`）做 checkpoint 限速；agent 每次自己判断要不要写。状态文件在当前 update folder 内，所以每个 update 的 turn count 是隔离的。

## 文件布局

super-manus 在使用它的项目里建出的磁盘布局（v0.5）：

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # 项目级，单一真相源
    │   ├── _index.md                           # 项目总览 + 模块清单 + 数据流（≤700 词）
    │   └── <module>.md                         # 每模块目标态（≤2000 词；/super-manus:prd-update 改）
    ├── e2e/                                    # v0.5 新增：常驻回归测试套，按 prd/ 镜像
    │   ├── _system/                            # 来自 prd/_index.md ## Demo 的跨模块场景
    │   │   └── test_<scenario>.<ext>           # test runner 自动发现；CI 每次 commit 跑
    │   └── <module>/                           # 来自 prd/<module>.md ## What users get 的能力测试
    │       └── test_<capability>.<ext>         # test runner 自动发现；CI 每次 commit 跑
    ├── roadmap.md                              # 项目级，模块状态表（自动管理）
    ├── prd_drift.md                            # 项目级，PRD ↔ 实现 drift 日志（append-only）
    └── impl/                                   # 每模块的里程碑时间序列
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # 时间戳唯一出现的地方
                ├── task_plan.md                # 这次迭代的 phase 索引
                ├── findings.md                 # 这次迭代的决定 / 错误 / 数据点
                ├── progress.md                 # 这次迭代的 commit + session log（hook 管理）
                ├── tasks/
                │   └── p<n>_impl.md            # 每 phase 的技术方案（懒加载，/super-manus:impl）
                └── tests/                      # v0.5 新增：phase 测试，里程碑级，CI 不自动发现
                    └── phase_p<n>_<verb>_<noun>.<ext>
```

两个测试目录不可互换：`e2e/` 是**常驻回归**（PRD 能力活多久就活多久，CI 自动发现）；`impl/<m>/<u>/tests/` 是**里程碑级 phase 测试**（跟着 update folder 提交，里程碑收尾后可归档，CI 不自动发现 —— 通过显式路径调用）。

## 自给自足的执行纪律 (v0.5)

super-manus 不再依赖任何别的 workflow 插件。它自带一份精简的执行层：

- **`tdd-in-phases` skill** —— `/super-manus:impl` 进入一个 phase 时，test-writer 在 code-writer 之前 spawn（不可商量）。Phase 测试写到 `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>`；当本 phase 完成一个能力，e2e 测试写到 `docs/super-manus/e2e/<module>/test_<capability>.<ext>`。test-writer commit 红测试；code-writer 翻绿，且禁止改测试。
- **`verification-before-phase-close` skill** —— phase Status 翻 `closed` 之前，`tasks/p<n>_impl.md ## Verification` 里的每条命令必须返回 0。orchestrator 跑（不是 code-writer）。`## Verification` 至少要包含：(1) 本 phase 的 phase 测试路径命令，(2) 一条用户可见的 smoke 命令（curl 端点、跑 CLI、打开页面）。
- **`systematic-debugging-in-phase` skill** —— 当 verify 命令失败，按 checklist 走（重读 Approach、重读失败测试、对 diff 二分查找、写一条回归测试，再 fix），别瞎试。同一类错误三次 → 上报。
- **3-agent `/super-manus:impl` 流水线** —— `impl-architect`（草拟 phase plan）、`impl-test-writer`（写 phase + e2e 测试，红）、`impl-code-writer`（写实现，绿）。这条流水线替换了 v0.4 的单 `impl-executor`。时间边界（test-writer 在 code-writer 之前 commit）+ 写权限边界（code-writer 不能改测试；orchestrator 哈希前后比对）+ persona 纪律（test-writer 把测试锚定在 PRD spec，不照 impl plan 镜像）—— 三条边界堵掉常见作弊路径。

如果你之前把 super-manus 和 `obra/superpowers` 一起装，现在不再需要了。v0.5 把 superpowers 里真正合 PRD-led loop 的三块（TDD / verify-before-completion / systematic debugging）吸收进来；其余要么和 super-manus 重叠（brainstorming、写计划、执行计划、subagent 调度），要么正交（git worktrees、收尾分支）。superpowers 装着不卸也行（用于 super-manus 之外的工作），或者卸掉。

## 不做的事

v0.5 保持精简。以下不在范围：

- 模块改名命令（频次低 —— 手动改文件夹 + 编辑 `prd/_index.md`）
- v0.2/v0.3 的迁移命令（手动：按 using-sm skill §8 移文件）
- 单个 super-manus 文件夹下的多产品 monorepo 支持（用多个 super-manus-enabled 子目录，一产品一份；或留在 v0.3）
- 代码评审 skill / agent —— 延后（`## Verification` + 3-pass drift gate 已经覆盖 load-bearing 的检查）
- 自动把 phase 测试升级成 e2e 套（手动：移文件 + 按命名约定改名）
- 给 v0.4 老项目回填 e2e 覆盖（自己补，或者等以后有 phase 触及那个能力时由 test-writer 顺手补）
- test-writer 与 code-writer 之间严格的读隔离（v0.5 走 open-read + 写边界 + persona 纪律 路线；后续如果作弊数据值得就再收紧）
- 多 harness 编排 / PR 创建 / 合并集成
- 测试框架 / runner —— super-manus 调用你项目已有的（`pytest`、`npm test`、`cargo test`、`go test`、`Makefile` 目标，等等）；不强加一个

## 状态

v0.5 —— 在 v0.4 项目级 PRD 之上，加自给自足的执行纪律（3-agent impl 流水线 + 3 个吸收过来的 skill）、常驻 e2e 回归测试套，以及新的 `/super-manus:impl-all` power-mode 命令。完整设计见 [docs/design-v0.5.md](docs/design-v0.5.md)。[docs/design-v0.4.md](docs/design-v0.4.md)（已弃用）、[docs/design-v0.2.md](docs/design-v0.2.md)（已弃用）、[docs/design-v0.1.md](docs/design-v0.1.md)（已弃用）保留作历史参考。
