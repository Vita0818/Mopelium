# Intatis 多 Agent 与文献研究能力迁移审计

审计日期：2026-07-11

目标仓库：Mopelium

参考仓库：`/Users/vita/Vitemis/Intatis`（全程只读）

## 后续执行状态（2026-07-11）

用户在审计后决定先固定 Intatis 当前工作区，避免两个项目继续变化导致参考基线漂移。现已在 `References/Intatis/` 建立惰性源码快照：包含 allowlist 范围内 184 个当前源/项目文件，并由 `References/Intatis/SNAPSHOT.md` 记录 dirty worktree 状态、短 HEAD、范围和排除项。

该动作解决了本报告原先关于“commit/tag 还是当前工作区”的基线选择：后续以这份当前工作区快照为迁移参考。它不是无差别的字节级仓库克隆；`.git`、构建缓存、生成工程、报告、运行态和凭据相关路径/文件名被排除，原 Intatis 仓库仍保持只读。

快照落地后已完成四个允许源码子树及 10 个根项目文件的逐字节复核，并运行 Mopelium SwiftPM build 验证参考目录未进入构建图。完整验证记录见 `docs/TESTING.md`；本次未运行 XCTest 或外部 E2E。

## 1. MODEL_CHECK_RESULT

- 当前 Agent：GPT-5 系列 Codex。
- 精确运行时 model id 无法从仓库或本地环境确认。

## 2. PATH_CHECK_RESULT

- Mopelium `pwd`：`/Users/vita/Vitemis/Virgo/Mopelium`
- Mopelium Git root：`/Users/vita/Vitemis/Virgo/Mopelium`
- 两者匹配预期。
- 审计开始及报告写入前，Mopelium `git status --short` 均为空。
- Intatis `pwd` / Git root：`/Users/vita/Vitemis/Intatis`
- Intatis 仅执行读取、搜索、统计与 Git 状态检查，没有写入、构建、测试、格式化或生成文件。

## 3. 执行摘要

结论先行：**可以复用 Intatis 源码，但不应只复制一个 `Orchestrator.swift`，也不应把 Intatis 整个产品无差别搬进 Mopelium。**

Intatis 的多 Agent 能力是一个闭合系统，而不是若干 AgentLoop 的递归调用：

```text
Typed IDs / Event schema / TaskContract / TaskGraph / Leases
                         ↓
EventLog + projections + durable replay
                         ↓
Permission + AgentKernel + scoped context
                         ↓
Scheduler + Mailbox + MessageBus + Mediator
                         ↓
Orchestrator + coordinator tools + UI/CLI host
```

其核心约束是：

1. Agent identity 是相对稳定的身份，角色属于当前 `TaskContract`。
2. 权限不是父 Agent 永久继承给子 Agent，而是当前任务的 `CapabilityLease` / `WorkspaceLease`。
3. `AgentLoop` 不直接同步递归调用另一个 `AgentLoop`。
4. 委派进入 TaskGraph 与 Scheduler；消息进入持久化 Mailbox/MessageBus。
5. 同一 Agent single-flight，不同 Agent 在显式并发上限内并行。
6. 所有任务状态、权限决定、工具 prepare/settle、租约和消息消费都写入 append-only EventLog。
7. 非幂等副作用在崩溃后不会盲目重放；不确定结果进入人工对账失败态。

Mopelium 已经迁移了 Intatis 的大部分旧版工具面，并有一个可用的单 Agent tool-calling loop，但尚未拥有上述多 Agent 控制面。当前最合理的方向是：

- 复制 Intatis 的**闭合内核切片**；
- 保留 Mopelium 自己的产品 UI 与文献研究定位；
- 把 Coordinator/Worker 的工具租约改成文献检索、文稿阅读、证据核验和报告产出；
- 不迁移与文献产品无关的 Code/Git/PR/CI 产品面；
- 在启用多 Agent 前，先补齐 Intatis 最新工具沙盒、WorkspaceLease 和权限门，否则并发会放大 Mopelium 当前的执行风险。

## 4. 审计范围与方法

### 4.1 Mopelium

已检查：

- 项目规则与全部要求文档：`AGENTS.md`、`docs/CURRENT_STATE.md`、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md`、`TESTING.md`、`NEXT_TARGET.md`。
- SwiftPM/XcodeGen：`Package.swift`、`project.yml`。
- 全部 47 个主要项目文件清单。
- `Apps/`、`Packages/`、`Tests/` 下全部 Swift 文件的声明、入口、关键调用链、工具 descriptor 和测试入口。
- 重点通读：CLI、Mac Chat、Tasks、Sources、Core config、Providers、AgentLoop、ToolProtocol、PathConfinement、文档/PDF、浏览器和工具测试。

当前统计：

| 项目 | 数量 |
|---|---:|
| 主要项目文件 | 47 |
| Swift/配置/测试主体行数 | 约 14,939 |
| XCTest `func test...` 入口 | 72 |
| `ToolRegistry.standard()` 工具名 | 53 |

### 4.2 Intatis

已检查：

- 项目规则与要求文档，包括 `COWORK_PRINCIPLES.md`。
- SwiftPM/XcodeGen 依赖图、11 个 library target、3 个 app target、10 个 test target。
- `Apps/` / `Packages/` 下全部 152 个 Swift 文件清单与逐模块声明索引。
- 完整阅读或分段核对多 Agent 核心：
  - `Task.swift` / `TaskGraph.swift` / `Leases.swift`
  - `Event.swift` / `CoworkEvents.swift` / `PermissionReview.swift` / `ToolExecution.swift`
  - `EventLog.swift` / `CoworkProjection.swift`
  - `AgentLoop.swift` / `ContextBuilder.swift` / `ContextProjection.swift` / `AgentExecutionBudget.swift`
  - `PermissionTypes.swift` / `DeterministicPolicyGate.swift` / `PermissionEngine.swift` / `SecretScanner.swift`
  - `AgentScheduler.swift` / `MessageBus.swift` / `Mediator.swift`
  - `CommunicationDelegationTools.swift` / `CoordinatorTools.swift` / `AskAgentTool.swift`
  - `Orchestrator.swift` 的 runtime、attach、restore、root task、delegate、spawn、scheduler、lease、tool registry、recovery、recycle 路径
  - `PermissionReviewControlPlane.swift`
  - macOS `CoworkViewModel` / project settings / CLI Cowork 接入。
- 对全部测试文件建立测试名称与覆盖面索引。
- 将 IntatisTools 与 MopeliumTools 做了重命名归一后的逐文件差异统计。

当前 Intatis 工作树统计：

| 项目 | 数量 |
|---|---:|
| Swift 文件 | 152 |
| Swift 总行数（含测试） | 约 55,689 |
| Source-only 行数 | 约 29,067 |
| 多 Agent 闭合核心（Core/Protocol/Conversation/Permission/AgentKernel/Cowork） | 约 14,870 行 |
| XCTest `func test...` 入口 | 487 |
| IntatisTools 工具名 | 58 |

## 5. 当前仓库状态与文档冲突

### 5.1 Mopelium

当前 Git 工作树是 clean，但 `docs/CURRENT_STATE.md` 和 `docs/DO_NOT_BREAK.md` 仍写着“当前工作区已有多处未提交改动”。这是已过时的状态描述。

采用当前 Git/source 为准的原因：工作区状态是实时事实，历史文档只能说明 2026-07-08 那一轮的上下文。

另一个轻微冲突是文档把 MopeliumTools 称为“完整 Intatis Tool Surface”。相对 2026-07-11 的 Intatis 当前源码，它已经不完整：Mopelium 有 53 个工具，Intatis 有 58 个，Mopelium 缺少：

- `git_remotes`
- `git_fetch`
- `git_pull_ff`
- `git_push`
- `git_switch`

这五个 Git remote/control 工具对文献产品并非必要，因此“不完整”不等于必须补齐；但文档应避免继续使用“与当前 Intatis 完全一致”的表述。

### 5.2 Intatis

Intatis 当前有大量未提交及未跟踪实现，包含多 Agent 可靠性、权限审查控制面、tool execution ticket、测试和文档更新。也就是说，本报告审计的是**当前工作树快照**，不一定等于某个可复现 Git commit。

Intatis 文档记录的 full SwiftPM baseline 是 331 tests，而当前源码静态统计得到 487 个 XCTest test 方法。原因很可能是当前工作树继续增加了测试但尚未形成新的统一验证基线。迁移前必须指定准确来源：

- 某个 commit/tag；或
- 明确授权采用当前未提交工作树快照，并先在 Intatis 内完成一次基线验证。

## 6. Mopelium 当前真实架构

### 6.1 模块

```text
MopeliumCore
  配置 / 错误 / 终端

MopeliumProviders
  普通 Chat + SSE + tool-calling 数据类型

MopeliumTools
  file / patch / shell / git / PDF / document-media / web / browser

MopeliumAgent
  OpenAI-compatible tool-call stream provider
  单 Agent 工具循环

CLI / MopeliumMac
```

它没有：

- typed AgentID / TaskID / LeaseID；
- append-only EventLog；
- TaskContract / TaskGraph / Scheduler；
- Mailbox / MessageBus / Mediator；
- CapabilityLease / WorkspaceLease；
- 三层权限门与持久化权限事件；
- 任务级 context projection；
- durable tool execution prepare/settle；
- 多 Agent restore/retry/cancel/reconcile。

### 6.2 单 Agent 链路

当前 `MopeliumAgentLoop`：

```text
messages
  -> 固定 system prompt
  -> 当前 side-effect policy 过滤 ToolRegistry.standard()
  -> provider.streamToolCalls
  -> 执行 tool calls
  -> observation 截断后以 role=tool 回灌
  -> 最多 12 轮
  -> 无 tool calls 时完成
```

其优点：

- 结构清楚，适合单次工具调用。
- 有 tool name/args/result 事件。
- 有基础 JSON object、required/type/additionalProperties 校验。
- 默认阻止 raw `run_shell`，write/destructive/shell 需要 UI/CLI 显式开关。
- 路径通过 `ToolContext(workspaceRoot:)` 和 `PathConfinement`。

其不足：

- policy 只按 side-effect 类别过滤，不能按 task lease 精确限制工具名。
- 没有 `PermissionEngine`、人工审批队列或 durable audit。
- 没有 task contract，worker 不知道“为何存在、向谁交付”。
- 没有 scoped context；Mac Chat 会把窗口完整历史继续送入模型。
- 工具调用没有 prepare/settle ticket，崩溃后无法判断副作用是否发生。
- 没有 usage/token budget、timeout/retry/recovery 状态机。
- 多个 tool calls 逐个串行；没有 Intatis 对独立 collaboration calls 的受控并行。

### 6.3 产品面

- `Chat`：真实 provider + 可选单 Agent tools。
- `Sources`：
  - 用户主动选择文件/文件夹；
  - UTF-8 文档/HTML/PDF 阅读；
  - DuckDuckGo HTML 搜索；
  - HTTP(S) 页面抓取；
  - 直接工具 console。
- `Tasks`：仍是 mock surface，源码明确写着没有 background workers。
- `Settings`：轻量配置状态。

因此目前最接近多 Agent 产品入口的是 `Tasks`，但真实数据链路应从 EventLog/Projection 驱动，而不是在现有 mock rows 上直接堆状态。

## 7. Intatis 多 Agent 实现详解

### 7.1 五个核心抽象

1. **Agent Identity**
   - `AgentID`、display/model/workspace/profile/coordination fuse。
   - “coordinator/worker”不是永久类层次；最终以当前 lease 决定工具。

2. **Task Contract**
   - objective、roleHint、expectedDeliverable、issuer、assignee、parent、related agents/tasks、workspace/capability lease、timeout、attempt limit、reply mode。

3. **Scoped Context**
   - global brief、task lineage、task-group events、direct messages、agent-local events、shared artifacts、workspace brief、allowed tools。
   - 有独立数量/字符预算。
   - 动态 task/message/event 数据放入明确的 user-role `UNTRUSTED_CONTEXT_DATA`，不会拼进 system role。

4. **Capability / Workspace Lease**
   - Worker 默认只获得读 workspace、list/search、read PDF、reply、request delegation。
   - Coordinator 显式获得 delegate/attach/message、Git/document/browser 等能力。
   - WorkspaceLease 固定 canonical path + device/inode identity，并有 read-only/read-write、allow/deny path rule。
   - task-scoped lease 在任务终态撤销。

5. **Task Graph + Scheduler**
   - 限制深度、hop、每 root task 数、active agent 数。
   - 拒绝 self-delegation、A→B→A cycle、重复 task。
   - 同一 assignee single-flight；不同 assignee 在 `maxConcurrentTasks` 内并行。

### 7.2 一条用户任务的完整生命周期

```text
用户输入
  -> GoalInputParser / mention route
  -> Orchestrator.send
  -> 创建 kind=root 的 TaskContract
  -> EventLog durable task_created / assigned / queued
  -> TaskGraph + Scheduler 内存 commit
  -> scheduler claim（同 agent single-flight）
  -> durable task_started
  -> 构建 task-scoped CapabilityLease / WorkspaceLease / ContextBundle
  -> AgentLoop
       -> provider stream
       -> tool call schema validation
       -> workspace identity/path check
       -> PermissionEngine
       -> durable permission request/resolution
       -> durable tool_execution_prepared
       -> 再次校验 workspace identity
       -> executor
       -> durable tool_result + tool_execution_settled
       -> observation 回灌
  -> task_completed / failed / cancelled + TaskReport
  -> revoke task leases
  -> 向父 Agent 返回 mediated Task Report
  -> 若为 tool-spawned child 且 idle，则自动 detach
```

### 7.3 为什么它不是递归 AgentLoop

Coordinator 模型调用 `delegate_task` 或兼容的 `ask_agent` 时：

- 工具只调用 `BusMessenger` / `Orchestrator` seam；
- Orchestrator 创建新的 durable TaskContract；
- Scheduler 在独立执行槽运行目标 Agent；
- 调用方等待 scheduler result；
- 目标结果经 MessageBus/Mediator 作为 ToolObservation 回到父 Agent；
- 父 AgentLoop 只是等待一个工具结果，没有在自己的调用栈中直接 new/run 子 AgentLoop。

这避免了：

- 无界递归；
- A→B→A 死循环；
- 同一 Agent 重入；
- 子 Agent 隐式继承父 Agent 权限；
- 无法取消/恢复的嵌套调用栈。

### 7.4 MessageBus 与 Mailbox

- `send_message`：普通通信，不创建 delegated task。
- `request_information` / `reply_message`：结构化问答通信。
- `request_delegation`：worker 请求上级帮助，但自己不能直接创建任务。
- `delegate_task`：真正创建 TaskContract。
- `ask_agent`：保留兼容，但内部仍走 scheduler，不嵌套 AgentLoop。
- Mediator 在转发前阻止 secret-looking 内容和超长原始 dump。
- 消息先持久化，再进入 mailbox。
- 只有确实投影给 Agent 且该轮成功完成的消息，才写 consumed event 并从 mailbox 移除。

### 7.5 恢复与副作用安全

Intatis 用 `ToolExecutionPreparedPayload` / `SettledPayload` 区分：

- 普通 read-only：可安全自动重放；
- write / exec / network / destructive / collaboration side effect：prepared 未 settled 时不能自动重放；
- 已 settled success 的非幂等 side effect 也不能通过整任务 retry 再执行一次。

EventLog 还使用：

- JSONL append-only；
- 跨进程 file lock；
- 锁内重读 tail seq；
- batch append；
- process-lifetime writer lease。

因此第二个 GUI/CLI runtime 不能同时调度同一 session。

### 7.6 自动权限审查

`@permission-reviewer` 是独立 control-plane agent：

- read-only、空工具 lease；
- 不进入普通 AgentScheduler；
- 不运行 AgentLoop；
- 独立 FIFO、single-flight、queue capacity、timeout、token budget、output ceiling；
- hard deny 不会送给 reviewer；
- self-review 拒绝；
- request 与 settled verdict 都必须先落 EventLog；
- model allow 只有 settled audit 成功后才能生效；
- timeout/invalid/provider failure 转人工 fallback；
- 迟到 allow 不能覆盖取消或 shutdown。

这是一个成熟但对 Mopelium v0.4 来说偏重的子系统。第一阶段可以保留人工 responder，第二阶段再迁移 automatic reviewer；但三层 deterministic gate 与 durable permission audit 不应省略。

## 8. Intatis 网络检索与文稿阅读实现

### 8.1 文稿读取

Intatis 的 Agent 工具包括：

- `read_file` / `list_files` / `search_text`
- `read_pdf`：PDFKit 文本抽取、页码选择、标题/页数 metadata。
- `edit_pdf_pages`：extract/split。
- `reconstruct_document_image`：调用已安装的 Docling/Marker/Tesseract 后端。
- `compile_latex`
- `generate_image`

重要设计：工具是 dumb executor；schema、permission、workspace lease、process sandbox 和 audit 在外层控制。

局限：

- 扫描 PDF 的 OCR 依赖外部命令，不是内置能力。
- 尚无文献领域的 DOI、作者、期刊、参考文献、引文关系等一等数据模型。
- `read_pdf` 返回文本观察，未构建页级 chunk index 或 citation anchor store。

### 8.2 网络检索

Intatis 有两层：

1. `web_fetch`
   - URLSession HTTP(S)；
   - 无登录态、无 JS；
   - bounded output。

2. `browser_*`
   - Node.js + Playwright persistent context；
   - Playwright 不可用时，用 Node built-in WebSocket + Chrome DevTools Protocol；
   - 驱动已安装 Chrome/Edge/Chromium；
   - profile/state/history/downloads 位于 workspace `.intatis/browser/`；
   - 同 profile 命令串行，不同 profile 可并行；
   - snapshot/action 返回可定位交互元素；
   - type 对 password/2FA/token/API key 目标做 Swift + DOM 双重拒绝；
   - history/profile/download inventory 仅返回 metadata。

局限：

- `browser_search` 本质是通用网页搜索，不是学术检索 API。
- 搜索结果没有稳定的 DOI/PMID/arXiv ID/作者/年份/venue schema。
- 不能仅靠网页可见文本保证引用准确性。
- persistent profile 对文献 app 的公开资料检索通常过重，应作为登录墙/JS 页面 fallback，而不是默认路径。

### 8.3 Mopelium 已有的对应能力

Mopelium Sources 页已经有一个更轻的 DuckDuckGo HTML 搜索和网页正文解析器，但这些类型当前是 `MopeliumSourcesScreen.swift` 内的 private UI service，Agent 无法直接调用。

建议把它抽成共享 service/tool，形成无浏览器的 `web_search`，再让 persistent browser 只作为 fallback。

## 9. IntatisTools 与 MopeliumTools 差异

### 9.1 已经高度相似

重命名归一后的差异显示：

- `FileTools.swift` 几乎一致。
- `PatchTool.swift` 几乎一致。
- Browser/PDF 工具主体仍高度同源。

因此文件/PDF/浏览器动作不需要重新从零实现。

### 9.2 最新 Intatis 的关键安全增强尚未进入 Mopelium

这是迁移多 Agent 前最重要的发现。

| 项目 | Intatis 当前实现 | Mopelium 当前实现 |
|---|---|---|
| raw `run_shell` | 实现保留，但 production registry 不暴露 | `ToolRegistry.standard()` 仍注册 |
| shell runner | macOS Seatbelt；Linux bwrap；缺 backend fail closed | `/bin/sh -c`，没有 OS sandbox |
| WorkspaceLease | root identity、access、allow/deny paths | 只有 workspace URL + PathConfinement |
| structured document process | `structuredShell`，network deny | 复用普通 `context.shell` |
| browser process | `networkStructuredShell`，明确网络权限 | 复用普通 `context.shell` |
| Git | 参数数组、lease 审计、remote guard | 较早的参数数组 wrapper，无最新 lease/remote hardening |
| production tool set | 58 个 descriptor 名；标准 registry 不含 raw shell | 53 个；标准 registry 含 raw shell |

虽然 Mopelium Chat 默认 policy 会单独阻止 `run_shell`，browser/document 的固定 wrapper 仍通过当前无 OS sandbox 的 `ProcessShellRunner` 执行。单 Agent 时风险已经存在；多 Agent 并行后，风险与资源竞争都会放大。

因此迁移顺序必须是：**先工具执行安全，再多 Agent 扩权。**

## 10. 哪些源码可以直接复制

“直接复制”的含义应是：复制一个依赖闭合、测试同步的模块切片，然后做命名和产品裁剪；不是逐文件散拷。

### 10.1 可高度复用

| Intatis 来源 | 建议 Mopelium 去向 | 处理 |
|---|---|---|
| Core `IDs.swift` | `MopeliumCore` | 重命名 typed IDs；保留 wire rawValue |
| Protocol `Task.swift` | 新 `MopeliumProtocol` | 直接迁移并保持 Codable 兼容 |
| Protocol `TaskGraph.swift` | `MopeliumProtocol` | 直接迁移；按研究任务调整 policy 默认值 |
| Protocol `Leases.swift` | `MopeliumProtocol` | 直接迁移；重定义 research capabilities |
| Protocol `ToolExecution.swift` | `MopeliumProtocol` | 直接迁移 |
| Cowork `AgentScheduler.swift` | 新 `MopeliumResearch`/`MopeliumCowork` | 直接迁移，保留 single-flight/snapshot |
| Cowork `MessageBus.swift` / `Mediator.swift` | 同上 | 直接迁移，保留 secret/size guard |
| Cowork communication/coordinator tools | 同上 | 迁移后改成 Mopelium 命名与研究文案 |
| AgentKernel `ContextBuilder` / `ContextProjection` | `MopeliumAgent` 或新 Kernel | 保留 untrusted user-role block 与 budgets |
| Artifacts | 新 `MopeliumArtifacts` | 很适合保存报告、证据表、PDF 派生产物 |

### 10.2 必须连同依赖一起改造

| Intatis 来源 | 原因 |
|---|---|
| `Orchestrator.swift` | 依赖 EventLog、TaskGraph、leases、AgentLoop、Permission、Tools、Providers、Projection |
| `AgentLoop.swift` | Provider/Usage/Event/Permission/ToolContext 类型均与 Mopelium 不同 |
| `EventLog.swift` | 依赖 Envelope/Event/typed IDs；应保持 schema 设计完整迁移 |
| `CoworkProjection.swift` | 依赖完整 event vocabulary |
| `PermissionReviewControlPlane.swift` | 依赖 PermissionReview protocol、provider usage、EventLog、fallback responder |
| `OpenAIToolCalling.swift` | Mopelium provider 更轻，需统一 request/chunk/finish/usage 模型 |
| 最新 `ToolProtocol` / `ShellGit` | 需要先引入 WorkspaceLease 与 IntatisCore 的 PathConfinement/SideEffect |

### 10.3 不建议复制到 Mopelium

- Intatis Code/Git/PR/CI 产品 UI。
- iOS app 与 SharedUI 全套。
- Intatis provider catalog/auth JSON 的完整复杂度，除非 Mopelium明确需要多 provider catalog。
- Git remote/control 工具；它们与文献检索无关。
- raw `run_shell` 的 model exposure。
- 历史兼容 UI 文案和 Intatis product naming。

## 11. 推荐的 Mopelium 目标架构

```text
MopeliumCore
  Config / Errors / Typed IDs / PathConfinement / PlatformProfile

MopeliumProtocol
  Event / Envelope / Task / TaskGraph / Leases / ToolExecution / Research events

MopeliumProviders
  Chat + ToolCalling + completion markers + usage + retry/timeout

MopeliumArtifacts
  reports / evidence tables / extracted text / generated files

MopeliumConversation
  EventLog / ResearchProjection / session replay

MopeliumTools
  Research registry + safe structured backends

MopeliumPermission
  deterministic gate / secret scanner / responder

MopeliumAgentKernel
  AgentLoop / ContextBuilder / ContextProjector / token budget

MopeliumResearch
  Orchestrator / Scheduler / MessageBus / Mediator / research tools

CLI / Mac
  Chat / Research Tasks / Sources / Settings
```

`MopeliumResearch` 比 `MopeliumCowork` 更符合产品定位；但内部仍可保留通用 task graph，不要硬编码永久 Researcher/Reader/Writer 类。

## 12. 文献研究定制建议

### 12.1 Task role，而非永久 Agent class

建议由 `@main` 按任务动态分配：

- literature discovery
- local corpus reader
- paper metadata resolver
- evidence extractor
- citation verifier
- contradiction/quality reviewer
- synthesis/report writer

同一个 Agent 可在不同 task 扮演不同 role；能力由 lease 决定。

### 12.2 Research Capability

建议替换通用 Intatis 能力枚举：

```text
read_local_corpus
search_local_corpus
read_pdf
reconstruct_document
search_public_web
fetch_public_page
search_scholarly_index
resolve_doi
read_bibliography
extract_evidence
verify_citation
write_report_artifact
send_message
request_information
reply_message
request_delegation
delegate_task
attach_workspace
```

默认 worker 不应获得：

- Git；
- patch；
- raw shell；
- destructive browser profile；
- 任意文件写入；
- spawn/remove/delegate（除非显式 coordinator lease）。

### 12.3 建议新增的领域工具

现有通用 web/browser 不足以支撑可靠文献产品。建议增加：

| 工具 | 输出 |
|---|---|
| `search_literature` | 结构化 title/authors/year/venue/DOI/URL/source |
| `resolve_identifier` | DOI/PMID/arXiv ID → canonical metadata |
| `fetch_abstract` | 来源、摘要、许可/可访问性 metadata |
| `read_document` | page-aware chunks + source anchor |
| `extract_references` | 原文 reference list + normalized candidates |
| `extract_evidence` | claim、quote-free paraphrase、page/section anchor、confidence |
| `verify_citation` | claim 与来源是否匹配、metadata 是否一致 |
| `build_evidence_table` | 多来源支持/冲突/空白矩阵 |
| `write_research_report` | ArtifactStore 中的 Markdown/JSON 报告 |

可优先使用公开、结构化、可追踪的 API/页面；persistent browser 只作 fallback。

### 12.4 建议新增的数据模型

```text
ResearchSource
  sourceID / canonicalURL / DOI/PMID/arXiv / title / authors / year / venue

SourceAnchor
  sourceID / page / section / paragraph-or-chunk

EvidenceItem
  claim / support-or-contradict / anchor / confidence / extractionAgent

CitationCheck
  citation / metadataMatch / claimMatch / warnings

ResearchReport
  objective / method / evidence / disagreements / limitations / bibliography
```

这些结构应进入 Event/Artifact schema，而不是只存在于 assistant 文本。

## 13. 推荐迁移阶段

### Phase 0：固定迁移基线

- 在 Intatis 选择明确 commit/tag 或经过验证的当前快照。
- 记录源文件清单和测试基线。
- Intatis 继续只读；所有修改发生在 Mopelium。

退出条件：迁移来源可复现。

### Phase 1：工具安全与 provider 可靠性

- 迁移最新 `WorkspaceLease`、root identity、denied paths。
- 把 `PathConfinement` 提升到 Core，避免 Tools/Permission 两份规则漂移。
- 迁移 Seatbelt/bwrap structured process runners。
- standard research registry 移除 raw shell/Git/destructive browser。
- browser/document 分离 network/non-network structured runners。
- 补 completion marker、usage、timeout/retry 与 provider error parity。

退出条件：单 Agent 工具链达到 Intatis 当前的 fail-closed 水平。

### Phase 2：协议与持久化骨架

- Typed IDs。
- Event/Envelope/EventLog。
- TaskContract/TaskGraph。
- CapabilityLease/WorkspaceLease。
- ToolExecution prepare/settle。
- ArtifactStore。

退出条件：root task、task lifecycle、tool ticket 可 append/replay。

### Phase 3：AgentKernel

- ContextBuilder/ContextProjector。
- strict AgentLoop outcome。
- PermissionEngine + manual responder。
- token budget。
- task-scoped tool registry。

退出条件：单 Agent 通过 TaskContract 运行，权限、工具和终态均可投影。

### Phase 4：Research Orchestrator

- Scheduler/Mailbox/MessageBus/Mediator。
- root task、delegation、communication、cycle/budget limits。
- coordinator tools。
- TaskReport 回传与 idle child recycle。
- cancel/retry/restore/manual reconciliation。

退出条件：两个 worker 可并行检索/阅读，`@main` 在同一 tool loop 收到结构化报告并综合。

### Phase 5：文献领域能力

- 结构化 scholarly search / identifier resolution。
- page-aware document chunks。
- evidence/citation/report models。
- research-only capability leases。
- report artifacts。

退出条件：报告中的每项核心结论都能追溯到 SourceAnchor。

### Phase 6：Mac/CLI 产品接入

- `Tasks` 从 mock 变为 EventLog projection。
- Sources 共享 service/tool 化。
- agent roster、task graph、evidence status、permission history。
- 不从 transcript 解析状态。
- CLI 增加 research session / resume / cancel / retry。

退出条件：UI 重启后能恢复 session/task 状态，且不重复非幂等操作。

### Phase 7：自动权限审查（可后置）

- 迁移 permission review protocol/control plane。
- 保留 manual fallback。
- 验证 request/settled durable-first、timeout/cancel/late allow。

## 14. 必须同步迁移的测试

最低回归矩阵：

### TaskGraph / Scheduler

- self-delegation 拒绝。
- A→B→A cycle 拒绝。
- worker 无 coordinator 工具。
- 同 Agent single-flight。
- 不同 Agent 遵守 concurrency limit。
- duplicate task / attempt / maxAttempts。
- root task 必须先 durable admission 再执行。

### Context

- task contract/lineage 可见。
- unrelated transcript 与其他 Agent private events 不可见。
- untrusted context 不能闭合边界或进入 system role。
- count/character budgets。
- consumed mailbox message 不再投影。

### Permission / Workspace

- hard deny 不到 reviewer。
- read-only worker 不能写。
- root path 替换在审批等待前后均 fail closed。
- lease 在终态撤销，retry 只能从历史安全续租。
- sensitive path/content 拒绝。

### Durable execution

- prepare 写失败时 executor 不运行。
- non-replayable prepared/unsettled 不自动恢复。
- settled success 不因整 task retry 重复执行。
- terminal event 写失败不伪装完成。

### Research

- search result metadata normalization。
- DOI/PMID/arXiv 去重。
- page/section anchor 稳定。
- citation mismatch 标记。
- 无来源 claim 不进入最终“已证实”结论。
- web worker 与 local reader 的报告可并行回传。
- synthesis 只能看到明确共享的 evidence/report。

## 15. 主要风险

| 风险 | 等级 | 说明 |
|---|---|---|
| 直接复制当前 Intatis dirty worktree | 高 | 无可复现 commit，文档/测试基线可能继续变化 |
| 只复制 Orchestrator | 高 | 依赖不闭合，容易退化为不安全的内存编排 |
| 先开多 Agent、后补工具沙盒 | 高 | Mopelium 当前 process runner 无 Intatis 最新 OS confinement |
| 复用完整 ToolRegistry.standard | 高 | 文献 worker 会看到 shell/Git/write/destructive 等无关能力 |
| 把完整 transcript 给每个 worker | 高 | prompt injection、隐私泄漏、上下文膨胀 |
| 用 assistant 文本推断 task/citation 状态 | 高 | 不可恢复、不可信、无法审计 |
| 只用 DuckDuckGo/浏览器文本做引文 | 中高 | metadata 与 claim anchor 不稳定 |
| 一次性搬入约 3 万行 Intatis 产品代码 | 中高 | 审查面过大，Mopelium 定位被稀释 |
| 延后自动权限 reviewer | 可接受 | 前提是 deterministic gate + manual responder 已完整存在 |

## 16. 最终建议

建议采用“**闭合内核复制 + 文献能力裁剪**”，而不是“整个 Intatis 改名”或“只复制多 Agent 文件”。

第一批真正应动手的代码范围应限定为：

1. `MopeliumCore`：typed IDs、PathConfinement、WorkspaceRootIdentity。
2. 新 `MopeliumProtocol`：Task/Graph/Lease/Event/ToolExecution。
3. 新 `MopeliumConversation` + `MopeliumArtifacts`：EventLog/projection/artifacts。
4. 新 `MopeliumPermission`：deterministic gate/manual responder。
5. 升级 `MopeliumTools` process sandbox，并创建 research-only registry。
6. 再迁移 AgentKernel/Cowork 的 scheduler/mailbox/orchestrator。

不建议第一批就改 Mac UI；先让 headless tests 证明 task graph、lease、durable execution 和两个 worker 的并行报告闭环，再接 `Tasks` 页面。

## 17. VALIDATION_RESULT

本轮是只读审计 + 文档报告：

- 已运行路径/Git root/status 检查。
- 已建立两个仓库的文件、行数、声明、tool descriptor、test 入口索引。
- 已对 IntatisTools/MopeliumTools 做归一化差异统计。
- 未运行构建/测试。
- 原因：用户明确要求先看完整项目并出报告、先不要改源代码；本轮没有代码行为需要构建验证，也没有在只读 Intatis 中执行会产生构建产物的命令。

报告完成后应运行：

```sh
git diff --check
git status --short
```

## 18. UNCERTAINTIES

- Intatis 当前工作树不是 clean；用户已明确选择当前未提交工作区快照作为迁移基线，来源与 dirty 状态已固化在 `References/Intatis/SNAPSHOT.md`。尚未决定未来如何刷新或对齐新的上游变更。
- 当前静态测试入口为 487，但文档 baseline 为 331；未运行测试，不能声明当前 487 tests 全部通过。
- 真实 provider、多 Agent 长任务、真实浏览器并发与 GUI E2E 仍是 Intatis 文档自己标记的 UNKNOWN，不能因源码存在而视为已验证。
- Mopelium 最终是否保留 Git/通用 browser profile/control surface，需要产品决定；从“专供文献检索与分析”定位看，默认应移除或隐藏。
- 学术数据源优先级、许可、速率限制、全文访问策略尚未由用户指定。

## 19. NEXT_RECOMMENDED_ACTION

当前工作树快照已经形成，下一步不应直接把 184 个文件接入构建，而应先从稳定快照中定义第一批闭合迁移切片。仍需用户决定 Mopelium 第一阶段采用完整 durable kernel，还是先做一个不承诺崩溃恢复的研究 MVP。

推荐选择：**迁移完整 durable kernel 的最小闭合切片，并把 Mopelium 工具集按文献产品收窄；先做 headless tests，再接 Mac UI。**
