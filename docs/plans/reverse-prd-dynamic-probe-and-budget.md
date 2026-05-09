# reverse-prd-architect 增强：动态探测 + 智能预算

## 问题诊断

`agents/reverse-prd-architect.md` 的静态分析骨架扎实——5 阶段模块发现、双源校验（LSP+grep）、drift
check 协议都到位了。问题出在两个维度：

| 维度 | 现状 | 后果 |
|---|---|---|
| 分析方式 | 纯静态（读源码 + LSP + grep） | 死代码当活模块、事件驱动连线断裂、动态配置看不到 |
| 工具预算 | 写死 `≤10 LSP + ≤30 grep/Read` | 小项目浪费、大项目炸穿、工具不分贵贱 |

## 核心设计：静态为底线，动态做交叉校验

静态分析**全程跑、不等任何人**。动态探测**顺手摸一把**，摸到就交叉比对提升准确度，摸不到不影响静态
流程继续走。

```
静态分析（必做，全程跑，底线）
    │
    ├── 读 compose / Makefile / 源码 / LSP / grep
    ├── 产出完整静态推断结果
    │
动态探测（并行尝试，顺手摸一把）
    │
    ├── curl / ps / logs 能摸到什么算什么
    ├── 摸到了 → 跟静态结果交叉比对
    ├── 摸不到 → 不影响静态流程
    │
    └── 发现 docker-compose.yml 但服务没跑
         → 告诉用户，不等用户，静态 PRD 照常出
         → 用户可以启动后要求重做交叉比对
    │
    ▼
交叉比对
    │
    ├── 两端一致  → 直接写入，不打标记
    ├── 静态独有  → 标 (audit — 运行时未验证)
    ├── 动态独有  → 标 (audit — 源码未覆盖)
    │
    ▼
写入 PRD
```

---

## 一、被动动态探测

**原则：只读不写，不启动服务，不改变系统状态。**

### 探测手段（按信息密度从高到低）

| 优先级 | 手段 | 命令/来源 | 收益 |
|---|---|---|---|
| 1 | 进程探测 | `ps aux`, `ss -tlnp`, `systemctl is-active` | 谁在跑，谁在监听端口 |
| 2 | API 契约抓取 | `curl --max-time 3 localhost:<port>/openapi.json` | 一次拿到真实接口列表，替代 20 次 Read |
| 3 | 数据库 Schema | `docker exec <pg> psql -c "\dt"`（只读） | 真实表结构，比 ORM 模型诚实 |
| 4 | 日志考古 | `logs/*.log`, `journalctl --last 50` | 系统"曾活着的痕迹" |
| 5 | CI 配置 | `.github/workflows/*.yml` | CI 里怎么启动、服务怎么连 |
| 6 | Git 考古 | `git log --stat -20`, `git log --diff-filter=D` | 高频改动 = 活跃，已删文件 = 废弃 |
| 7 | 测试收集 | `pytest --collect-only` | 测试实际 import 了什么 |
| 8 | 包锁文件 | `poetry.lock`, `package-lock.json` | 精确依赖图 |

探针分两类实现：

- **通用探针**（零参数）—— `ps aux`、`ss -tlnp`、`docker ps`、CI/Git 考古、锁文件检查。
  收敛到一个 `scripts/probe-runtime.sh`，Agent 一行调用拿到原始事实（进程列表、端口、容器名、
  文件存在性）。
- **定向探针**（需要静态分析喂参数）—— `curl <port>/openapi.json` 的端口来自 compose/env 推断，
  `docker exec <name> psql` 的容器名来自 compose，`pytest --collect-only` 的框架来自
  pyproject.toml。Agent 用静态分析的发现作为参数，按需发起。

### Docker 发现时的处理

```
发现 docker-compose.yml
  → 尝试连接服务端口
    ├─ 连接成功 → 抓取运行时数据
    └─ 连接失败 → 不在中间步骤阻塞。告诉用户：
                  "docker-compose.yml 存在但服务未运行，动态探测跳过。
                   运行 docker compose up -d 后我可以补做交叉比对。
                   先用纯静态结果出 PRD。"
                  → 静态分析照常继续，不等用户
```

### 降级

动态探测失败（连接拒绝/超时/无 Docker）→ 不做任何重试 → 直接跳过该探针 → 标记对应结论为
`(audit — 服务未运行，基于源码推断)`。不影响静态流程。

---

## 二、智能工具预算

替换当前写死的 `≤10 LSP + ≤30 grep/Read`。

### 按模块数动态分配

```
预算 = 10（基础池） + 5 × N_modules（模块增量） + 10（动态探测池）
硬上限 = 60

单模块  → 25 次，充裕
12 模块 → 60 次上限
```

### 两级熔断

```
80%（Soft limit）
  → 停止广度探索（不再开新模块源码阅读）
  → 进入"收割模式"：把已有发现写入 PRD，来不及验证的打 (audit — 预算不足)
  → 绝不清空已收集的信息

100%（Hard limit）
  → 强制停止
  → 输出已完成部分 + 未完成模块清单
  → 绝不抛异常全盘丢弃
```

### 工具性价比分级

```
[一发入魂] 动态探针  — curl openapi / psql / docker ps       1 次 ≈ 20 次 Read
[全局地图] LSP workspace_symbols                             1 次拿全项目导出符号
[快速确认] Glob                                               1 行结果确认/排除假设
[精准打击] Read（入口文件 <200 行）                            核心路由/Schema
[精确连线] Grep（限定目录 + 精确符号）                         调用关系
[按需使用] LSP find-references                                每模块 ≤3
[最后手段] Read（大文件 >1000 行）/ Grep（宽泛关键词）         预算充裕时才用
```

两层协同：高密度探针天然省预算 → 省下的预算给需要深读的模块 → 正向循环。

---

## 三、(audit) 标记扩展

```
(audit — 服务未运行)   动态探测失败，基于源码推断
(audit — 预算不足)     硬上限触发，来不及验证
(audit — 数据源冲突)   静态与动态结论矛盾，保留差异
```

已有的裸 `(audit)` 标记保留，由 agent 按场合选用子类或裸标记。

---

## 四、改动范围

**改动文件：**
- `agents/reverse-prd-architect.md` — prompt 层改动
- `scripts/probe-runtime.sh`（新增） — 通用探针脚本

| 位置 | 改动 |
|---|---|
| 原 `## Budget: ≤10 LSP + ≤30` | **删除** |
| `## Deliverables` 之前 | 新增 `## Runtime probe` 节 — 探测清单 + 降级 + Docker 提示 |
| 原 Budget 位置 | 替换为 `## Tool budget` 节 — 动态公式 + 软硬熔断 + 工具优先级 |
| `## (audit) policy` | 扩展三类子标记，保持向后兼容 |

**不改：**
- `commands/reverse-prd.md`（编排逻辑不变）
- `skills/using-sm/SKILL.md`（协议不变）
- 工具集（Bash 已有，不需要新工具）
- 命令行接口（`/super-manus:reverse-prd` 调用方式不变）
- 任何其他文件

---

## 五、不做的事

- 不让 agent 安装任何东西
- 不加新 agent 类型
- 不做有副作用的主动流量触发（如向业务接口发请求获取 Trace-ID）
