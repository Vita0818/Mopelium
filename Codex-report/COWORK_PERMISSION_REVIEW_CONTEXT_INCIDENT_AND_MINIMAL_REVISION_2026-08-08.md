# Cowork 权限审查上下文缺口事件与最小修订方案报告

- 报告日期：2026-08-08
- 设计状态：已与用户确认的当前实施方向
- 重点 session：`cowork_w89crmx9`
- 影响范围：Cowork 自动权限审查的上下文输入
- 本轮修改范围：仅新增本报告，并在 2026-08-07 事件报告中增加方案替代说明；未修改业务代码、配置或测试

## 1. 最新决策

本次最终确认的修订方向是：

> 不再把当前 submission 的最新一句用户消息或当前 `TaskContract.objective` 单独当作权限审查的
> 完整用户目标。需要权限审查时，由正在请求工具的 agent 模型根据它实际拥有的上下文，生成一份
> 有界的 `Authorization Context Report`（授权上下文汇报），再把这份汇报连同当前用户指令、
> 原始用户证据和宿主解析出的 exact tool facts 一起交给权限 reviewer。

对于本次暴露问题的 `@main` root task，报告由 `@main` 使用其 Cowork 主线程模型上下文生成。普通
worker 若将来进入同一流程，只能依据其被投影的 task-scoped context 生成，不能因此获得
`@main` 的完整 thread。

这是一个集中在“权限审查输入边界”的最小修订，不先修改：

- TaskGraph 或 scheduler；
- 每次 Send 创建新 root `TaskContract` 的语义；
- Goal / WorkTask / ContinuationRun；
- 浏览器工具和 durable tool execution；
- CapabilityLease、WorkspaceLease 或三层权限门；
- UI 中对“继续、重试、恢复”的专用交互。

这里的“最小”指只改变 reviewer 获得语义上下文的方式。由于当前系统尚不存在 agent 生成并传递该
报告的字段，真实实现不会只是机械替换一行取值；仍需要一个小型、additive 的生成与传递接口。

## 2. 事件摘要

本事件最初表现为浏览器工具在真实网页流程中连续失败，随后依次暴露了两个不同层面的问题。

第一层是浏览器工具实现缺陷：interactive snapshot 的嵌套脚本转义错误、异常被吞成空控件列表、
以及动作前 target miss 没有被准确标记为 `not_started`。这些问题已经在此前获得授权后修复，并通过
工具、AgentLoop、真实 CDP smoke、SwiftPM 和 macOS Debug build 验证。

第二层是在浏览器工具恢复能力已经生效后暴露出的权限上下文缺口：

1. 用户向 `@main` 提交了完整的 arXiv 搜索与下载测试任务；
2. `@main` 成功打开 arXiv、搜索并定位目标论文；
3. 一次 provider streaming connection lost 中断了该 root task；
4. 用户随后发送 `Continue.`；
5. `@main` 的主线程模型历史使其知道应继续原来的 arXiv 流程；
6. 但每次 Send 都建立新的 root `TaskContract`，新 objective 只有 `Continue.`；
7. `@main` 再次提出 `browser_type` 时，自动 reviewer 只收到当前任务和当前工具调用的窄上下文；
8. reviewer 无法从 `Continue.` 证明高风险网络/浏览器动作与用户任务的关系，因此按 fail-closed 规则拒绝；
9. 最终模型产生了说明报告，但 runtime 正确地把任务结算为 failed。

因此，这次权限拒绝不是浏览器网络故障、模型缺少多模态能力，也不是 reviewer 单纯“不够聪明”。
reviewer 缺少的是 main 已经拥有、但没有被投影到权限控制面的语义连续性。

## 3. 关键 EventLog 事实

`cowork_w89crmx9` 的 canonical EventLog 已确认以下顺序：

| EventLog seq | 事实 |
| --- | --- |
| 884 | 用户提交完整 arXiv 端到端任务 |
| 983—994 | `browser_navigate` 成功 |
| 1064—1065 | 测试提示词使用了 schema 不支持的 `exact` 参数，调用在输入校验阶段失败 |
| 1106—1117 | 故意使用错误 locator；工具返回 `effectDisposition=not_started`，模型能够继续 |
| 1212—1223 | 新 snapshot 成功 |
| 2159—2170 | 搜索框输入成功 |
| 2333—2344 | 第 3 页结果中出现目标论文 |
| 2437—2448 | 标题 target miss 被识别为动作前失败，未进入人工对账 |
| 2514—2519 | provider streaming connection lost，原 root task 中断 |
| 2520 | 用户发送 `Continue.`，形成新的 submission/root task |
| 2697 | 新 root 尝试 `browser_type` |
| 2701 | 自动 reviewer 因目标只有 `Continue.` 而拒绝 |
| 3816 | main 生成完整失败说明 |
| 3819—3824 | runtime 追加 denied side effects、failed turn/task/submission 终态 |

这些事实证明浏览器的 pre-action recovery 修复已经工作；真正阻断后续流程的是权限 reviewer 的
上下文输入，而不是 browser backend 再次卡死。

## 4. 当前源码的真实权限审查流程

### 4.1 新用户输入成为当前 root objective

`Orchestrator.admitNextMainRootTask` 每次处理 composer submission 时建立新的 root
`TaskContract`，其 `objective` 直接使用本轮 `text`。因此：

```text
用户输入：Continue.
当前 TaskContract.objective：Continue.
```

源码入口：

- `Packages/IntatisCowork/Sources/Orchestrator.swift:2946`
- `Packages/IntatisCowork/Sources/Orchestrator.swift:2995`

### 4.2 main 与 reviewer 使用不同的上下文投影

对于正常的 `@main` root submission，Orchestrator 为 main 选择 `.coworkMainThread` history policy。
因此 main 的 provider 请求能够使用其独立、可恢复的跨轮模型历史。

源码入口：

- `Packages/IntatisCowork/Sources/Orchestrator.swift:6694`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3227`

权限 reviewer 不复用这条模型历史。它运行在独立 control plane 中，只收到一条固定 system prompt
和一条由宿主拼装的 user prompt，并且 `tools: []`。

源码入口：

- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:712`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1360`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1380`

### 4.3 工具调用先由宿主解析

main 提出工具调用后，ToolRegistry 从 exact registration 和规范化参数中解析：

- concrete tool identity；
- canonical permission/action；
- secret-redacted `PermissionActionPreview`；
- `PermissionIntent`；
- side effect、network risk 和 touched paths；
- capability/workspace membership；
- argument digest 和字符数；
- task、agent、attempt 和 tool-call identity。

这些事实来自宿主和工具实现，不由 reviewer 猜测。

源码入口：

- `Packages/IntatisTools/Sources/ToolProtocol.swift:583`
- `Packages/IntatisTools/Sources/ToolProtocol.swift:1017`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:570`

### 4.4 只有 ask-class 调用进入自动 reviewer

生产 Cowork 默认使用没有 in-engine reviewer 的 `PermissionEngine()`。确定性 gate 的 hard deny 保持
终局，明确 allow 可直接通过；需要交互审查的结果由 `AgentPermissionResponder` 送入独立
`PermissionReviewControlPlane`。

源码入口：

- `Packages/IntatisPermission/Sources/PermissionEngine.swift:4`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3026`
- `Packages/IntatisCowork/Sources/AgentPermissionResponder.swift:10`

### 4.5 AgentLoop 当前怎样提供“用户目标”

AgentLoop 构建 `PermissionRequestContext` 时主动填写：

```text
causalContext.userGoal = current TaskContract.objective
```

同时填写当前 task lineage、agent、lease、intent、gate、authorization snapshot 等结构化事实。

源码入口：

- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3146`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3201`

这意味着正常新式 Cowork 请求中，control plane 几乎总能收到非空 `userGoal`，并不会用更早的用户
任务替换它。

### 4.6 Control plane 虽读取完整 EventLog，但只发送窄摘要

`PermissionReviewControlPlane` 在每次审查前执行 `log.replayChecked()`，但完整 EventLog 只作为验证和
投影输入，并不会原样发送给 reviewer。

`makeReviewTask` 的合并优先级是：

1. 优先采用 AgentLoop 已提供的 task、lease、contract 和 causal context；
2. 只有字段缺失时才从 CoworkProjection/EventLog 派生；
3. `causalContext.userGoal` 非空时不会被派生 goal 覆盖；
4. `eventSequenceNumbers` 为空时，才根据当前 lineage/request/tool call 派生少量事件编号。

源码入口：

- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:602`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1139`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1172`

正常派生事件只覆盖：

- 当前 task/root/parent lineage 的生命周期事件；
- 当前 `toolCallID`；
- 当前 permission `requestID`；
- 与当前 task 直接绑定的 agent message；
- 额外加入最近一条符合条件的 user message。

普通派生路径最多保留 20 个 sequence。它不会自动加入前一个 root task、前一 submission 的工具结果、
main 的完整 assistant history 或整个网页 observation。

源码入口：

- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1320`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1902`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:2034`

## 5. 当前交给 reviewer 的信息及来源

最终 reviewer prompt 包含以下主要信息：

| 信息类别 | Prompt 中的内容 | 权威来源 |
| --- | --- | --- |
| Review identity | review task/request ID | PermissionReviewControlPlane |
| Invocation identity | requesting agent、task/root/parent、attempt、toolCallID | AgentLoop + TaskContract |
| Exact tool | tool name、concrete tool ID、registry version、descriptor digest | ToolRegistry |
| Action preview | 有界、脱敏、可标记 truncated 的语义参数 | 具体 Tool registration |
| Permission intent | action/resources/metadata/data/control/risks/replay | 具体 Tool implementation |
| Deterministic gate | decision/risk/reason/policy version | DeterministicPolicyGate |
| Arguments | digest + character count；Cowork 不发送 raw JSON | ToolRegistry/AgentLoop |
| Capability boundary | lease ID、task、communication/delegation 摘要 | CapabilityLease |
| Workspace boundary | lease ID、root、access、allow/deny path rules | WorkspaceLease |
| Current task | objective、role、deliverable、issuer/assignee | 当前 TaskContract |
| Current causal goal | 当前 `TaskContract.objective` | AgentLoop |
| Active roster | agent/model/profile/workspace 摘要 | EventLog attach/detach events |
| Related events | 当前 lineage/request/tool call 的有界摘要 | EventLog + 固定筛选规则 |

当前不存在：

- 一个正式的 `AuthorizationGoal` 协议字段；
- 一个正式的 `AuthorizationContextReport` 协议字段；
- 在 reviewer 之前运行的上下文整理模型；
- 把 main 的 `.coworkMainThread` 模型历史直接投影给 reviewer 的逻辑。

当前最接近 Authorization Goal 的三个值都是当前 task objective：

- `TaskContract.objective`；
- `PermissionReviewCausalContext.userGoal`；
- `ResolvedToolAuthorization.taskObjective`。

## 6. 根因

根因是数据面与控制面的语义上下文不对称：

```text
@main data plane
  能看到跨轮 Cowork main-thread history
  知道 Continue. 指向原 arXiv 任务

@permission-reviewer control plane
  只看到当前 root task objective = Continue.
  当前 lineage 不包含前一个 root task
  无法证明 browser_type 与 Continue. 的关系
```

系统错误地把两个不同概念压在同一个字段中：

- `latest user instruction`：用户这一轮具体说了什么；
- `authorization context`：当前动作在整个任务中为什么合理。

对“创建 auto.txt”这样的完整单轮指令，两者可能相同；对“继续、重试、接着做、按刚才方案执行”，
两者必然不同。

## 7. 已确认的最小修订方案

### 7.1 新的语义流程

当前流程：

```text
current TaskContract.objective
  -> causalContext.userGoal
  -> permission reviewer
```

修订后：

```text
requesting agent 已拥有的模型上下文
  -> agent 模型生成 Authorization Context Report
  -> host 绑定当前 tool call 与用户证据
  -> permission reviewer

current user message
  -> latest_user_instruction（单独保留）
```

对于当前 root/main 场景，报告作者是 `@main`。reviewer 不负责自己整理原始长历史，也不要求用户重新
复述完整任务。

### 7.2 Authorization Context Report 的内容

报告应由模型用自然语言高度概括，但采用固定语义段落，至少回答：

```text
Authorization Goal
  用户原本要完成什么。

Current Progress
  当前已经完成什么、在哪里中断、哪些步骤尚未完成。

Latest User Instruction
  用户本轮的原始增量指令是什么。

Current Action Justification
  当前 exact tool call 为什么是继续完成目标所需的一步。

Scope Assessment
  当前动作是否延续原范围，还是包含新增、修改或撤销的要求。
```

文字长度必须有界并经过现有 secret sanitizer；具体字符上限在实现阶段依据 provider context policy 和
现有 permission preview 预算确定，本报告不虚构固定数值。

### 7.3 用户消息仍是授权证据

agent 生成的汇报用于解释上下文，不应被当成 agent 可以给自己创造权限的声明。因此 reviewer 输入中
仍需分别保留：

- `latest_user_instruction`：本轮用户原话；
- supporting user event references：报告所依据的用户消息 EventLog seq/稳定 ID；
- 由宿主从这些引用读取、限长和脱敏后的用户证据摘要；
- 当前 exact tool authorization、gate 与 leases。

宿主只接受同一 session 中真实存在的 user-message 引用。agent 不能通过报告文本扩大 deterministic
gate、CapabilityLease、WorkspaceLease 或工具注册表提供的权限上限。

### 7.4 建议的 additive 数据形状

为了旧 JSONL 继续解码，不建议直接改变现有 `userGoal` 的历史语义。最小安全形状可以是等价于：

```text
PermissionReviewCausalContext
  userGoal                         // legacy/current compatibility
  authorizationContextReport?     // model-generated bounded report
  latestUserInstruction?          // raw user instruction, sanitized/bounded in prompt
  reportAuthor?                    // requesting agent identity
  supportingUserEventSequences[]  // host-validated EventLog evidence
  taskLineage[]
  eventSequenceNumbers[]
```

字段名称可在实现时遵循现有 Swift 命名和 JSON 兼容约定调整，但语义必须分开，不能继续把
`Continue.` 同时解释为最新指令和完整授权目标。

### 7.5 报告生成位置

报告必须由请求该工具的 agent 模型生成，而不是由权限 reviewer 自己猜：

- `@main` root task：使用 main 已有的 `.coworkMainThread` 模型上下文；
- task-scoped worker：只能使用 worker 被授予的 scoped context；
- reviewer：只消费报告和证据，不生成报告，也不获得工具；
- host：负责选择输入、绑定身份/turn/tool call、验证引用、脱敏、持久化和 fail-closed。

模型报告如何从 provider response 可靠携带到 AgentLoop，需要实现前核对当前
`ToolCallingProvider`/`AgentMessage` 协议。推荐优先使用结构化、request-bound 的内部字段；如果现有 wire
不能在同一次 tool-call response 中可靠携带，则使用一次有界、无工具、同 agent model 的报告生成请求。
不得从任意自由文本气泡猜测或截取授权报告。

### 7.6 Reviewer prompt 的变化

旧 prompt 的关键问题：

```text
task_contract objective=Continue.
causal_context goal=Continue.
```

新 prompt 应至少明确分栏：

```text
authorization_context_report:
  Authorization Goal: 在 arXiv 搜索指定论文并下载目标文件。
  Current Progress: 已定位论文；provider 中断后尚未完成下载。
  Latest User Instruction: Continue.
  Current Action Justification: browser_type 用于恢复未完成的搜索/进入下载流程。
  Scope Assessment: 延续原任务，没有扩大范围。

latest_user_instruction: Continue.
report_author: @main
supporting_user_events: [884, 2520]
exact_tool: browser_type
action_preview: <host-resolved, redacted>
deterministic_gate: <host-resolved>
capability_lease: <host-resolved>
workspace_lease: <host-resolved>
```

上述 report 和 user excerpts 继续放在 untrusted quoted data 区域。reviewer system prompt 必须明确：

- 报告是 agent 对上下文的汇报，不是独立授权；
- 用户消息证据、确定性 gate、tool authorization 和 leases 才是权限边界；
- 报告与证据冲突、缺失或包含未经用户支持的范围扩大时拒绝；
- reviewer 只能收窄，不能放宽 hard deny 或 lease ceiling。

### 7.7 缺失或异常时的行为

以下情况必须维持 fail-closed：

- report 缺失且最新指令不足以证明调用；
- report 生成失败、超时或格式无法识别；
- report author 与 requesting agent 不匹配；
- report 绑定的 turn/toolCall/request 已变化；
- supporting user event 不存在、不是 user message、属于其他 session 或无法验证；
- report 声称的目标与用户证据冲突；
- report 试图扩大 workspace、capability、network 或 destructive scope；
- report 含秘密或越过 sanitizer 的不可安全内容。

失败时不得静默切换人工授权、复用旧 reviewer allow 或绕过 durable settlement。

## 8. 修订前后的行为变化

### 8.1 本次 `Continue.` 场景

修订前：

```text
用户目标：Continue.
工具：browser_type
证据：当前新 root 的少量事件
结果：reviewer 无法证明调用合理，deny
```

修订后：

```text
授权上下文：继续原 arXiv 搜索下载任务
当前进度：已完成搜索与论文定位，下载未完成
最新指令：Continue.
当前动作：browser_type，精确动作预览由 host 提供
用户证据：原始任务消息 + Continue. 消息
结果：reviewer 可以基于完整语义判断；若 exact action 仍在原范围内则可 allow
```

“可以 allow”不等于预先批准。每个 exact tool call 仍需独立审查，reviewer 仍可因 locator、URL、路径、
参数范围、风险或 lease 不一致而拒绝。

### 8.2 用户扩大范围

例如用户原任务是下载论文，后来明确要求“下载后再上传到公开网站”。报告必须把上传列为范围变化，
并引用该新增用户消息。若报告隐瞒变化或没有支持证据，reviewer 应拒绝相关上传工具调用。

### 8.3 用户撤销要求

如果用户后来明确说“不要下载，只阅读摘要”，报告必须反映撤销。旧任务消息不能覆盖较新的撤销指令；
请求下载时 reviewer 应拒绝。

## 9. 为什么这是当前最小方案

该方案直接修复已证实的单一断点：reviewer 的语义上下文来源。

它不要求立即建立：

- 自然语言 `Continue/继续` 分类器；
- previous root task 的 durable continuation binding；
- UI 中的 Retry/Resume 选择器；
- task/submission 关系重写；
- 全 session transcript projection；
- 新的权限模式或第二套 runtime。

此前 2026-08-07 报告建议优先实现 host-owned durable continuation binding。该方案仍可作为未来更严格
的恢复、UI 和审计增强，但不再是解决当前 reviewer 上下文缺口的第一实施步骤。本报告记录的
Authorization Context Report 是当前最新、优先的修订决策。

## 10. 不得随本修订改变的安全边界

本修订只增加审查信息，不增加执行权限。以下合同保持不变：

1. deterministic hard deny 永远终局；
2. reviewer 只能 allow/deny ask-class 请求，不能自行执行工具；
3. reviewer 使用 `tools: []`，不进入普通 TaskGraph/AgentLoop；
4. CapabilityLease 和 WorkspaceLease 仍是权限上限；
5. exact tool identity、action preview、intent、argument digest 仍由 host/tool registry 提供；
6. raw secret、cookie、token、完整网页内容和 raw tool output 不进入 reviewer prompt；
7. permission request/settlement 继续 durable-first；
8. allow 只有成功写入唯一 settlement 后才能交付 executor；
9. timeout、malformed output、provider/persistence failure 和 cancellation 继续 fail-closed；
10. 旧 EventLog/JSONL 必须继续解码。

## 11. 建议实现触点

实现阶段预计只需围绕权限上下文链路修改，主要入口是：

### 11.1 Protocol

- `Packages/IntatisProtocol/Sources/PermissionReview.swift`
  - 为 causal context 增加 additive/optional 报告、最新指令、作者和证据引用；
  - 保持旧字段与旧 JSONL decode 兼容。

### 11.2 AgentKernel

- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift`
  - 在 ask-class permission request 前获得 request-bound report；
  - 将 report 绑定到当前 turn/task/toolCall/requesting agent；
  - 当前 `userGoal: contract?.objective` 不再承担完整授权上下文职责。

### 11.3 Cowork control plane

- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift`
  - 验证报告身份与 supporting user events；
  - prompt 分开显示 report 与 latest instruction；
  - 保留 exact tool/intent/gate/lease 事实；
  - 报告异常继续 fail-closed。

### 11.4 Provider/context bridge

- 核对 `Packages/IntatisProviders` 的 ToolCalling response 与
  `Packages/IntatisAgentKernel` 的 `AgentMessage`/model history 结构；
- 选择可靠的结构化同响应载体，或有界的同-agent无工具报告调用；
- 不从 UI bubble 或任意 assistant prose 猜测 report。

### 11.5 Tests

- `Packages/IntatisCowork/Tests/PermissionReviewControlPlaneTests.swift`
- `Packages/IntatisCowork/Tests/AutomaticPermissionReviewTests.swift`
- 必要时增加 AgentLoop/model-history 交界测试。

本方案不要求修改 browser tool executor；若实现阶段发现必须修改 ToolRegistry 或每个具体 Tool schema，
应先停下重新评估，因为那意味着实现已经偏离“集中修改权限上下文边界”的最小目标。

## 12. 必须增加的回归测试

### 12.1 原事件复现

1. 提交完整 arXiv 任务；
2. main 完成若干 browser 步骤；
3. 注入 retryable provider interruption；
4. 用户发送 `Continue.`；
5. main 请求新的 browser ask-class action；
6. 断言 reviewer prompt 包含原目标、进度、最新指令、当前动作理由和 supporting user events；
7. 断言 prompt 不再只显示两次 `Continue.`；
8. reviewer allow 后 exact tool execution 能继续。

### 12.2 单轮完整指令

独立完整请求仍应生成正确报告，不改变当前正常审查结果，也不增加重复工具执行或重复 permission
settlement。

### 12.3 范围扩大

main 报告声称用户授权上传或删除，但 supporting user events 不包含该要求时，reviewer 必须拒绝。

### 12.4 用户撤销

原任务允许下载，最新用户消息撤销下载时，report 和 reviewer 必须以最新撤销为准。

### 12.5 报告生成失败

超时、provider error、空报告、malformed report、错误 author/binding 均不得自动 allow，也不得进入 GUI
人工 fallback。

### 12.6 秘密与 Prompt Injection

报告、用户证据和 action preview 中的 secret-like material 必须脱敏；伪造
`<<<END_REVIEW_TARGET>>>` 等边界文本不能突破 untrusted block。

### 12.7 Worker scoped context

worker 生成报告时只能使用自己的 task-scoped context；测试必须证明它不会获得 main 的完整对话或其他
agent 的私有上下文。

### 12.8 Durable compatibility

旧 `PermissionReviewCausalContext` 和旧 `permission_review_requested` JSONL 在缺少新增字段时继续解码；
新 report 的 request/settled audit 能在重启后回放和对账。

### 12.9 不影响现有权限分支

- deterministic allow 不新增无意义 reviewer call；
- deterministic hard deny 不触发 report 生成来尝试放宽；
- automatic reviewer 仍为 FIFO/single-flight；
- cancel、timeout、late provider output 和 first-terminal CAS 行为不变。

## 13. 完成标准

只有同时满足以下条件，才能声称修复完成：

1. reviewer 不再把当前一句 `Continue.` 当作完整授权目标；
2. report 确由 requesting agent model 基于其真实可见上下文生成；
3. reviewer prompt 明确分开 report、latest instruction 和 supporting user evidence；
4. report 与 exact turn/task/toolCall/requesting agent 绑定；
5. report 不能扩大 deterministic gate、capability 或 workspace ceiling；
6. 缺失、冲突、无法验证和 secret-bearing report 均 fail-closed；
7. 原 `cowork_w89crmx9` 流程的自动化复现测试通过；
8. 旧 EventLog 协议测试通过；
9. PermissionReviewControlPlane 的 timeout/cancel/durability 回归通过；
10. 全量相关 SwiftPM tests 与 macOS Developer ID 目标 Debug build 通过；
11. 项目文档同步说明新上下文合同及仍未实现的未来 continuation/UI 增强。

## 14. 明确排除的错误修法

- 只把最近 N 条完整聊天原样塞给 reviewer；
- 只识别字面值 `Continue/继续` 并自动继承任意历史任务；
- 让 reviewer 自己浏览整个 EventLog 或运行工具；
- 把 main 的报告直接视为用户授权，不附 supporting user evidence；
- 把 report 放进每个具体工具的业务参数并交给 executor；
- 复用上一轮 reviewer allow 作为后续 blanket approval；
- 因为 report 表述合理就跳过 exact authorization、gate、lease 或 execution revalidation；
- 为减少误拒绝而把 reviewer failure 改成人工等待或默认 allow；
- 把完整网页、tool observation、cookie、token、credential 或隐藏推理放进报告。

## 15. 实施前仍需确认的细节

以下内容不影响已经确定的产品/安全语义，但实现前需要通过源码和 provider conformance test 选择：

1. 当前 provider wire 是否能在同一 assistant tool-call response 中可靠携带独立的结构化 report；
2. 若不能，额外 no-tools report request 如何复用 exact agent binding、取消与 timeout；
3. supporting user event 应由模型返回稳定引用，还是由 host 根据报告生成输入自动绑定；
4. report 的字符/token 预算与截断策略；
5. 同一 turn 多个 ask-class tool call 是否复用 report base，并为每次 exact action 追加 justification；
6. report generation failure 是否记录新的 typed failure kind，还是复用现有 reviewer/context failure；
7. 新字段在 UI 是否只作为调试/审计显示，默认产品界面是否隐藏。

这些细节必须标记为实现待确认，不能在没有源码验证时假定已经存在。

## 16. 源码与证据入口

### 当前 root 与 main history

- `Packages/IntatisCowork/Sources/Orchestrator.swift:2946`
- `Packages/IntatisCowork/Sources/Orchestrator.swift:2995`
- `Packages/IntatisCowork/Sources/Orchestrator.swift:6694`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3227`

### Permission request

- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3026`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3146`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3201`
- `Packages/IntatisProtocol/Sources/PermissionReview.swift:46`

### Reviewer control plane

- `Packages/IntatisCowork/Sources/AgentPermissionResponder.swift:10`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:602`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1139`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1320`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1360`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1380`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1902`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:2034`

### Tool authorization

- `Packages/IntatisTools/Sources/ToolProtocol.swift:583`
- `Packages/IntatisTools/Sources/ToolProtocol.swift:1017`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:136`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:570`

### Prior incident report

- `Codex-report/COWORK_BROWSER_PERMISSION_CONTINUATION_INCIDENT_2026-08-07.md`

## 17. 最终判断

浏览器工具当前没有被本事件证明存在新的硬性阻断；真正导致本次端到端流程停止的是自动权限 reviewer
获得了错误粒度的任务语义：main 知道完整故事，reviewer 只知道 `Continue.`。

当前敲定的修复不是让 reviewer 读取完整对话，也不是先建立复杂 continuation 系统，而是在现有
permission request 边界上增加一份由 requesting agent 模型生成、由宿主绑定用户证据和 exact tool
facts 的 `Authorization Context Report`。最新用户消息继续单独保留，报告负责解释完整任务关系，
用户消息继续作为授权来源，确定性 gate 和 leases 继续作为不可扩大的权限上限。

这是目前能够直接修复已观察缺口、同时保持 Cowork 安全边界和架构简洁性的最小方案。
