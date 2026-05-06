# super-manus

> 🌐 **语言**: [English](README.md) · **简体中文**

*在 `/clear` 后存活，从 git 历史生成开发可读的进度日志，与 superpowers 并存（不是 fork）。*

## 是什么

**super-manus** 是 Claude Code 插件，把 [obra/superpowers](https://github.com/obra/superpowers) 的执行纪律和 Manus 风格（[OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)）的文件级持久化状态拼到一起。它**只负责状态层**：磁盘上一份项目级文件夹存放 PRD、计划、findings、进度日志，hooks 在你工作时帮你保持同步。

## 为什么

`superpowers` 给你 TDD、subagent 调度、code-review 纪律，但 `/clear` 或 `/compact` 后全丢。`planning-with-files` 给你 Manus 风格的跨 session 持久化状态，但没有执行纪律。

super-manus 补的是中间这块缺口：跨 session 边界仍存活的状态，加上 hooks 自动恢复"我们刚才在做什么"，不需要你手动维护。它**不**重新实现 superpowers 的 executor —— super-manus 只管**状态层**。执行继续用 superpowers（或别的 workflow）。

## v0.4 — 项目级全局 PRD

v0.4 把 PRD / roadmap / prd_drift 提到项目级，去掉了 v0.3 那个"每个 feature 一个时间戳目录"的包装。v0.3 的布局是 `docs/super-manus/<YYYY-MM-DD>-<feature>/`，把两个不同概念混在一起：PRD（项目当前状态的快照）和 impl（每次迭代的时间序列）。v0.4 把它们分开：

- **PRD 是项目级的**（`docs/super-manus/prd/`），一个模块一份文件（db / api / frontend / ...）。每份模块 PRD 允许在 `## What users get` 段写 schema 草图、接口轮廓、UX 流 —— PM 给工程的细节量级 —— 上限 ~2000 词。下面有 9 个稳定标题（Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions）。项目级 `prd/_index.md` 在 Problem / Demo / Must / Not doing / Modules / Data flow overview 之上，多了 Audience + Success metrics 两段。
- **实现按模块按里程碑**：每次"里程碑迭代"是 `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/` 下的一个文件夹，含四件套（`task_plan.md`、`findings.md`、`progress.md`、`tasks/p<n>_impl.md`）。老 update 是不可变历史记录，最新的是 active。**时间戳只出现在这里**。
- **PRD ↔ 实现对齐是强制的**：当 intent 与 PRD 偏离，agent 停下，写到 `prd_drift.md`，问用户：回退实现，还是跑 `/super-manus:prd-update <module>`。PRD 永不静默更新。
- **没有 active 状态文件**。v0.2/v0.3 的 `.super-manus/active` 指针没了。Hooks 用 `docs/super-manus/impl/<module>/*/` 的 mtime 扫描自动 resolve 当前 active update。"feature" 这个抽象消失了 —— 一个项目 = 一份 PRD。

完整设计见 [docs/design-v0.4.md](docs/design-v0.4.md)。v0.2/v0.3 设计保留在 [docs/design-v0.2.md](docs/design-v0.2.md)（已弃用）。

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

super-manus 在使用它的项目里建出的磁盘布局（v0.4）：

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # 项目级，单一真相源
    │   ├── _index.md                           # 项目总览 + 模块清单 + 数据流（≤700 词）
    │   └── <module>.md                         # 每模块目标态（≤2000 词；/super-manus:prd-update 改）
    ├── roadmap.md                              # 项目级，模块状态表（自动管理）
    ├── prd_drift.md                            # 项目级，PRD ↔ 实现 drift 日志（append-only）
    └── impl/                                   # 每模块的里程碑时间序列
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # 时间戳唯一出现的地方
                ├── task_plan.md                # 这次迭代的 phase 索引
                ├── findings.md                 # 这次迭代的决定 / 错误 / 数据点
                ├── progress.md                 # 这次迭代的 commit + session log（hook 管理）
                └── tasks/
                    └── p<n>_impl.md            # 每 phase 的技术方案（懒加载，/super-manus:impl）
```

## 不做的事

v0.4 保持精简。以下不在范围：

- 每模块的测试文件夹（测试设计意图写在 `prd/<module>.md ## Quality bar`；每天的测试结果写在当前 update 的 `findings.md`）
- 模块改名命令（频次低 —— 手动改文件夹 + 编辑 `prd/_index.md`）
- v0.2/v0.3 的迁移命令（手动：按 using-sm skill §8 移文件）
- 单个 super-manus 文件夹下的多产品 monorepo 支持（用多个 super-manus-enabled 子目录，一产品一份；或留在 v0.3）
- TDD 任务执行器 / subagent 调度 / 代码评审 / 多 harness —— 仍然延后
- 自动测试运行（用你已有的工具链）
- PR 创建或合并集成

## 与 superpowers 并存

super-manus 和 superpowers 可以同装，不冲突：

- super-manus 拥有 SessionStart / Stop / PostToolUse hooks 的**状态层**。
- superpowers 拥有自己的 SessionStart hook 用于 skill bootstrap —— 两个都触发，都注入，互不干扰。
- super-manus 的 skill 不会自动触发；`using-sm` 只在你跑 `/super-manus:*` 时被调用。
- superpowers 的 `writing-plans` 写出来的计划（`docs/plans/*.md`）独立于 super-manus。

## 状态

v0.4 —— 项目级 PRD，模块 × 里程碑两轴模型，含 drift detection。完整设计见 [docs/design-v0.4.md](docs/design-v0.4.md)。v0.2/v0.3（[docs/design-v0.2.md](docs/design-v0.2.md)，已弃用）和 v0.1（[docs/design-v0.1.md](docs/design-v0.1.md)，已弃用）保留作历史参考。
