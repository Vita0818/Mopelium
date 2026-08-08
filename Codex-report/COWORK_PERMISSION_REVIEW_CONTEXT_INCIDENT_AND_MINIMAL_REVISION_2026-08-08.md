# Cowork 权限审查上下文缺口事件与最小修订方案报告

- 报告日期：2026-08-08
- 设计状态：已与用户确认的当前实施方向
- 重点 session：`cowork_w89crmx9`
- 影响范围：Cowork 自动权限审查的上下文输入
- 源码核对基线：Mopelium HEAD `23678e6b452347d4aff41dc4f85fd949727ccf70`；
  `SNAPSHOT.md` 记录的 Intatis 来源 commit `2d849dbe592a4532a23d0b5a0f84c4e52e459505`
- 本轮文档修订范围：把原报告收敛为最新确认方案；未修改业务代码、配置或测试

## 1. 最新决策

本次最终确认的修订方向是：

> 不再把当前 submission 的最新一句用户消息或当前 `TaskContract.objective` 单独当作权限审查的
> 完整用户目标。对 automatic ask-class 工具调用，在现有 `PermissionReviewCausalContext` 中新增一个
> 可选 `authorizationContext` 对象。请求工具的同一个 agent 模型基于它真正看到的上下文生成有界、
> 结构化的 `Authorization Context Report`；宿主把模型选择的临时用户证据句柄映射为真实 EventLog
> sequence、补齐中间用户消息，再将报告、原始用户证据和 exact tool facts 一起交给 permission reviewer。

对于本次暴露问题的 `@main` root task，报告由 `@main` 使用其 Cowork 主线程模型上下文生成。普通
worker 若将来进入同一流程，只能依据其被投影的 task-scoped context 生成，不能因此获得
`@main` 的完整 thread。

三个关键来源必须保持分离：

- `report` 由 requesting agent 的同一模型根据 exact provider-facing context 生成，只是未经信任的语义解释；
- `supportingUserEventSequences` 的候选由模型用临时句柄选择，最终 sequence、连续性补齐和合法性由宿主决定；
- 最新用户原话、报告作者和 exact invocation binding 不新增副本，分别从 canonical `user_message`、现有
  `requestingAgent` 和现有 `PermissionReviewTask` / `ResolvedToolAuthorization` 读取。

当前 `AgentMessage` / `AgentChunk` 没有可靠的独立 sidecar 可在原 tool-call response 中携带该报告。因此
已确定使用一次 request-owned、同 agent、同 exact inference binding、`tools: []` 的额外模型请求生成报告，
而不是从 assistant prose、UI bubble 或特定字符串中猜测。该请求只发生在 automatic ask-class 调用；
deterministic allow、hard deny 和人工模式不增加这次调用。

这是一个集中在“权限审查输入边界”的最小修订，不先修改：

- TaskGraph 或 scheduler；
- 每次 Send 创建新 root `TaskContract` 的语义；
- Goal / WorkTask / ContinuationRun；
- 浏览器工具和 durable tool execution；
- CapabilityLease、WorkspaceLease 或三层权限门；
- UI 中对“继续、重试、恢复”的专用交互。

这里的“最小”指改动面集中在 reviewer 获得语义上下文的边界。协议只增加一个 additive optional
wrapper，但运行时还必须实现报告请求的 timeout/cancel、严格解析、token 计量、证据映射和 durable
fail-closed，因此它是“小范围、中等实现量”的安全关键修订，不是机械替换一行取值。

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

- `Packages/IntatisCowork/Sources/Orchestrator.swift:6756`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3236`

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

- `Packages/IntatisTools/Sources/ToolProtocol.swift:1020`
- `Packages/IntatisTools/Sources/ToolProtocol.swift:1144`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:570`

### 4.4 只有 ask-class 调用进入自动 reviewer

生产 Cowork 默认使用没有 in-engine reviewer 的 `PermissionEngine()`。确定性 gate 的 hard deny 保持
终局，明确 allow 可直接通过；需要交互审查的结果由 `AgentPermissionResponder` 送入独立
`PermissionReviewControlPlane`。

源码入口：

- `Packages/IntatisPermission/Sources/PermissionEngine.swift:4`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:1966`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3036`
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
- 一个正式的 `PermissionAuthorizationContext` / `AuthorizationContextReport` 协议字段；
- 在 reviewer 之前运行的上下文整理模型；
- 把 main 的 `.coworkMainThread` 模型历史直接投影给 reviewer 的逻辑；
- 在当前 `AgentMessage` / `AgentChunk` 中与 tool-call response 并列传输独立结构化 report 的 sidecar。

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
requesting agent 正常生成 tool call
  -> host 解析 exact tool / args / intent / action preview / gate / leases
  -> automatic ask-class ?
       no  -> 保持现有 allow / hard-deny / manual 路径
       yes -> 同 agent、同 exact binding、tools: [] 的报告请求
            -> model 返回结构化 report + 临时用户证据句柄
            -> host 映射句柄、补齐证据闭包、限长并脱敏
            -> authorizationContext 嵌入当前 permission request
            -> control plane 验证并 durable-first 交给 reviewer
```

这个流程不对“继续、重试、恢复”等自然语言做字符串分类。是否需要报告只由已经存在的 deterministic
permission 结果和 automatic/manual mode 决定；报告的语义内容由请求工具的模型从其实际上下文概括。

### 7.2 Authorization Context Report 的内容

报告由 requesting agent 的同一模型生成，不是用户原文，也不是宿主机械截取。模型收到：

- 该 agent 刚才真正使用的 provider-facing context snapshot；
- 当前 assistant tool-call batch；
- 宿主解析出的 exact action preview、intent、gate 和不可扩大的 lease 摘要；
- 宿主为该 agent 可见的真实用户消息生成的临时句柄 `U1`、`U2`……。

报告请求禁用工具，只接受严格、有界的 JSON。等价输出形状为：

```json
{
  "report": {
    "authorization_goal": "用户原本要完成什么",
    "current_progress": "已完成什么、在哪里中断、还缺什么",
    "latest_instruction_interpretation": "本轮增量指令在当前上下文中的含义",
    "current_action_justification": "当前 exact tool call 为什么是必要的一步",
    "scope_assessment": "是否延续原范围，或包含新增、修改、撤销"
  },
  "supporting_user_handles": ["U2", "U5"]
}
```

模型不能返回持久 EventLog sequence、报告作者、authorization ID 或 binding digest。宿主严格解析后只
保留 canonical report，并把句柄转成经验证的 EventLog 引用。报告字段必须逐项限长并经过现有 secret
sanitizer；具体字符/token 上限属于实现参数，必须依据真实 provider/context policy 确定，本报告不虚构数值。

### 7.3 关键信息的来源和信任级别

| 信息 | 产生者 | reviewer 如何使用 |
| --- | --- | --- |
| `report` | requesting agent 的同一模型 | 未经信任的语义解释，不能独立授权 |
| `supportingUserEventSequences` | 模型选择临时句柄；宿主映射、校验并补齐 | 指向 canonical 用户证据 |
| 最新用户原话 | 宿主按当前 submission/任务关系从 EventLog 读取 | 较新的撤销、限制和范围变化优先 |
| 报告作者 | 现有 `PermissionReviewTask.requestingAgent` | 宿主权威身份，不让模型自报 |
| exact action / gate / leases | ToolRegistry、AgentLoop 和现有 authorization snapshot | 不可由报告扩大 |
| turn/task/tool-call binding | 现有 review task 和 `ResolvedToolAuthorization` | ControlPlane 继续执行一致性校验 |

只有 `report` 的语义正文由模型生成。用户授权事实仍来自 EventLog 原文；最终证据集合和 exact request
绑定仍由宿主负责。

### 7.4 Additive 数据形状

为了旧 JSONL 继续解码，不改变现有 `userGoal` 的历史语义。只在
`PermissionReviewCausalContext` 中增加一个 optional wrapper：

```swift
public struct PermissionReviewCausalContext: Codable, Equatable, Sendable {
    // 既有字段保持不变
    public var userGoal: String?
    public var authorizationContext: PermissionAuthorizationContext?
    // issuer / assignee / taskLineage / relatedAgents / eventSequenceNumbers ...
}

public struct PermissionAuthorizationContext: Codable, Equatable, Sendable {
    public var report: PermissionAuthorizationReport
    public var supportingUserEventSequences: [Int]
}

public struct PermissionAuthorizationReport: Codable, Equatable, Sendable {
    public var authorizationGoal: String
    public var currentProgress: String
    public var latestInstructionInterpretation: String
    public var currentActionJustification: String
    public var scopeAssessment: String
}
```

这里刻意不新增三个重复字段：

- 不新增 `latestUserInstruction`：从 canonical current user event 读取；
- 不新增 `reportAuthor`：现有 `requestingAgent` 已是权威来源；
- 不新增持久化 `bindingDigest`：使用现有 exact invocation/authorization 结构绑定。

一个 optional wrapper 还避免了原草案四个并列 optional 字段可能出现“有报告但没有证据”之类的半完整
状态。wrapper 存在时，report 和证据引用必须同时通过验证；旧事件缺少 wrapper 时仍可正常解码。

### 7.5 为什么不新增 binding digest

当前 `PermissionReviewTask` 已携带 session、request、turn、agent、task/root/parent、attempt、
toolCall 等身份，`ResolvedToolAuthorization` 已绑定 exact tool、参数摘要、task objective、gate 和
leases；ControlPlane 会逐项复核，完整 review task 又作为一个 `permission_review_requested` 事件原子持久化。

把 digest 与报告一起写入同一事件，不会形成新的独立信任根；能够同时改写事件的人也能同时改写 digest。
它最多是调试指纹，不能替代现有结构校验。因此最小协议不保存 `bindingDigest`。如果未来确需审计
fingerprint，可从 canonical requested event 派生，而不是把它宣称为新的授权边界。

### 7.6 报告请求的生命周期

报告只在以下条件全部满足后生成：

1. host 已解析 exact tool registration、normalized arguments、intent、action preview 和 lease membership；
2. deterministic gate 结果不是 hard deny；
3. authorization snapshot 已完成当前执行前的一致性复核；
4. 当前是 automatic ask-class permission flow。

生成请求必须：

- 使用 requesting agent 当前 provider-facing conversation 的不可变快照，并包含刚生成的 assistant
  tool-call batch；
- 使用该 agent 的 exact frozen inference binding，不能回退 current/default 或借用 reviewer provider；
- 通过现有 `ToolCallingProvider.stream` 发出 request-owned、`tools: []` 的普通无工具请求；
- 不创建嵌套 `AgentLoop`，不占普通 scheduler 槽，不写 UI bubble，也不进入该 agent 的后续模型历史；
- 传播 consumer termination，并使用有界 timeout/cancel；late output 对当前或后续 permission request
  没有能力；
- 计入该 session/turn 适用的模型 usage 统计；
- 对同一 assistant batch 中每个 automatic ask-class exact tool call 分别生成并绑定报告。初版不跨
  tool call 复用，避免 action justification 串用。

当前 provider wire 不需要修改：原 tool-call response 仍按现有协议返回；报告使用第二次、无工具的
provider request。每个 automatic ask-class tool call 因而最多增加一次模型推理和相应延迟/token 成本。

### 7.7 Supporting user evidence 的句柄和闭包

模型不直接获得或返回 durable sequence。宿主先从该 agent 被授权、实际可见的上下文投影中，为真实
user-message 建立仅对本次 report request 有效的临时句柄：

```text
U1 -> EventLog seq 884
U2 -> EventLog seq 2520
```

模型只能返回 `U1`、`U2`。宿主随后：

1. 验证句柄确实来自同一 session、同一 requesting agent 的授权上下文投影；
2. 映射成真实 user-message EventLog sequence，拒绝 assistant/tool/system/其他 session 的引用；
3. 无条件加入当前 submission 对应的 canonical 用户消息；
4. 从最早被引用用户消息到当前用户消息，按 EventLog 顺序加入该授权投影内所有真实用户消息，形成
   evidence closure，防止模型跳过中途的撤销、限制或范围变化；
5. 对 worker 只允许其 task-scoped projection 和合法 task lineage 内证据，绝不扩展为 main thread；
6. 通过 complete-known-history、sequence 连续性、事件类型和预算检查后，才写入
   `supportingUserEventSequences`；
7. 从这些 sequence 读取原文，限长、脱敏后提供给 reviewer。

unknown future event、history gap、cross-session 引用、不可证明的 projection、缺失当前用户消息或证据闭包
超出安全预算，都必须 fail closed。模型的 handle 选择只是相关性提示，不是删除较新用户约束的权力。

### 7.8 Reviewer prompt 的变化

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
  Latest Instruction Interpretation: 用户要求从中断位置继续原任务。
  Current Action Justification: browser_type 用于恢复未完成的搜索/进入下载流程。
  Scope Assessment: 延续原任务，没有扩大范围。

latest_user_instruction: Continue.             // host 从 canonical user event 读取
requesting_agent: @main                        // 现有 review task 字段
supporting_user_events: [884, 2520]
supporting_user_excerpts: <host-read, bounded, sanitized>
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

### 7.9 缺失或异常时的行为

以下情况必须维持 fail-closed：

- automatic ask-class request 缺少完整 `authorizationContext`；
- report 生成失败、超时或格式无法识别；
- report request 未使用 requesting agent 的 exact frozen binding 或实际上下文快照；
- report 被错误附着到另一个 turn/task/toolCall/request；
- supporting user event 不存在、不是 user message、属于其他 session 或无法验证；
- 模型返回未知句柄，或宿主无法建立完整 evidence closure；
- report 声称的目标与用户证据冲突；
- report 试图扩大 workspace、capability、network 或 destructive scope；
- report 含秘密或越过 sanitizer 的不可安全内容。

报告阶段失败必须在现有 permission lifecycle 中产生 durable typed deny；不得静默切换人工授权、复用旧
reviewer allow、绕过 durable settlement，或只在内存中返回一个不可审计的错误。

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

### 8.4 不限于 Continue 的一般语义引用

该机制同样覆盖：

- “按刚才的方案执行”；
- “重试，但不要覆盖现有文件”；
- “选择第二个方案”；
- “把它发给刚才那个 agent”；
- worker 根据 task-scoped delegation 继续一项被中断的子任务；
- 用户在多轮中增加、缩小或撤销范围。

这些场景都不依赖窄字符串表。requesting agent 负责解释语义关系；宿主负责证明其引用的用户消息真实、
连续且未漏掉较新的约束；reviewer 再针对当前 exact action 作最终收窄判断。

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

### 9.1 相比原报告与中间讨论方案的收敛

原报告的方向已经正确，但仍把若干实施选择留待确认；后续讨论中还短暂考虑过额外 digest。当前方案
把它们统一收敛如下：

| 原报告或中间讨论状态 | 当前确定方案 | 收益 |
| --- | --- | --- |
| report、latest instruction、author、evidence 四个并列 optional 字段 | 一个 optional `authorizationContext` wrapper，内部要求 report + evidence 同时有效 | 减少重复事实源和半完整状态 |
| 同响应 sidecar 或额外请求二选一 | 明确使用同 agent、无工具的额外请求 | 无需修改 provider wire，不从自由文本猜测 |
| 模型稳定引用或宿主自动绑定尚未确定 | 临时句柄 + 宿主映射 + evidence closure | 模型不能伪造 seq 或省略较新撤销 |
| exact binding 只描述为要求 | 复用现有 review task 与 resolved authorization 的结构绑定 | 不重复 session/task/tool-call 身份 |
| 后续讨论曾考虑增加 binding digest | 不持久化 digest | 避免把同事件内的校验值误称为独立安全边界 |

因此，当前方案的优势不是引入了比原报告更强的新授权来源，而是把每个字段的 provenance、生成时机、
transport、验证责任和失败行为都确定下来，同时删去可以从现有权威结构派生的重复字段。

### 9.2 复杂度和运行成本

这个修订的协议表面很小，但实现不能按“只加两个字段”估计。主要复杂度集中在 AgentKernel 的额外
provider request 生命周期：

- 捕获 exact provider-facing context snapshot；
- 复用 requesting agent 的 frozen inference binding；
- 严格 JSON decode、字段预算和 secret sanitization；
- timeout、cancel、consumer termination、late output 和 usage accounting；
- 多个 ask-class tool call 的 request ownership；
- report failure 的 durable typed denial；
- EventLog evidence mapping、closure 和 complete-known-history 检查。

运行时只有 automatic ask-class 调用增加成本：每个 exact call 最多多一次无工具模型请求。deterministic
allow、hard deny、manual approval 和不经过权限审查的工具不增加请求。初版按 exact call 隔离报告，
不做跨调用缓存；后续若 provider 原生支持可靠 sidecar，可以在不改变 durable schema 的情况下优化掉
第二次请求。

### 9.3 预计改动量

以下是基于当前源码结构的 source-derived 估算，不是已经完成的代码统计：

| 范围 | 预计生产代码 | 说明 |
| --- | ---: | --- |
| Protocol additive types | 约 30–70 行 | optional wrapper、typed report、旧 JSON decode |
| AgentKernel reporter + hook | 约 180–320 行 | 建议用一个内部 helper，AgentLoop 只保留接线 |
| ControlPlane validation/prompt | 约 100–200 行 | 证据闭包、结构校验、prompt 分栏 |
| 合计 | 约 300–550 行 | 3 个现有源码文件，最多新增 1 个内部 helper |

安全回归测试预计约 500–900 行，通常会多于协议代码本身。总体判断是：**改动面小、实现量中等、权限
关键路径风险高**。它不是架构重写，也不是十几行补丁。

## 10. 不得随本修订改变的安全边界

本修订只增加审查信息，不增加执行权限。以下合同保持不变：

1. deterministic hard deny 永远终局；
2. report 是 requesting agent 的未信任陈述，不是用户授权，也不能单独证明 action 合理；
3. canonical 用户消息、exact authorization、gate 和 leases 才构成可验证的权限边界；
4. reviewer 只能 allow/deny ask-class 请求，不能自行执行工具；
5. reporter 和 reviewer 都使用 `tools: []`，都不进入普通 TaskGraph 或嵌套 AgentLoop；
6. CapabilityLease 和 WorkspaceLease 仍是权限上限；
7. exact tool identity、action preview、intent、argument digest 仍由 host/tool registry 提供；
8. raw secret、cookie、token、完整网页内容和 raw tool output 不进入 reporter/reviewer prompt；
9. permission request/settlement 继续 durable-first；
10. allow 只有成功写入唯一 settlement 后才能交付 executor；
11. timeout、malformed output、provider/persistence failure 和 cancellation 继续 fail-closed；
12. 旧 EventLog/JSONL 必须继续解码；
13. report generation 不得改变 deterministic allow、hard deny 或 manual permission 的现有语义。

## 11. 建议实现触点

实现阶段预计只需围绕权限上下文链路修改，主要入口是：

### 11.1 Protocol

- `Packages/IntatisProtocol/Sources/PermissionReview.swift`
  - 为 causal context 增加一个 additive/optional `authorizationContext`；
  - 增加 `PermissionAuthorizationContext` 和 typed `PermissionAuthorizationReport`；
  - wrapper 内只持久化 canonical report 和 host-validated user event sequences；
  - 不新增 latest-instruction、author 或 binding-digest 副本；
  - 保持旧字段与旧 JSONL decode 兼容。

### 11.2 AgentKernel

- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift`
  - 保留当前 provider-facing conversation 和 assistant tool-call batch 的不可变快照；
  - 在 exact authorization/gate 解析和复核后，仅为 automatic ask-class call 请求 report；
  - 复用 requesting agent 的 exact inference binding，以 `tools: []` 发起 request-owned provider call；
  - 严格 decode、限长、脱敏并将 report 附着到当前 permission request；
  - 正确传播 timeout/cancel/consumer termination、usage 和 late-output fence；
  - 当前 `userGoal: contract?.objective` 不再承担完整授权上下文职责。

建议新增一个 AgentKernel internal helper，例如 `PermissionAuthorizationContextReporter.swift`，集中封装
report prompt、strict decode、预算、请求生命周期和句柄选择；`AgentLoop` 只负责在正确的 exact call
边界接线。该 helper 不是新 runtime、不是 scheduler agent，也不能递归调用 `AgentLoop`。

### 11.3 Cowork control plane

- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift`
  - 验证 optional wrapper 是否在 automatic ask-class 请求中完整存在；
  - 复核 supporting sequence 的 session、事件类型、agent projection、顺序和 complete-known history；
  - 无条件加入当前用户消息并建立从最早引用到当前消息的 evidence closure；
  - 从 canonical EventLog 读取最新指令和 bounded/sanitized 用户证据；
  - 继续复用现有 requestingAgent、turn/task/toolCall 和 authorization snapshot 作 exact binding；
  - prompt 分开显示 untrusted report、canonical latest instruction 和 supporting evidence；
  - 保留 exact tool/intent/gate/lease 事实；
  - 报告异常继续 fail-closed。

### 11.4 Provider

当前 `Packages/IntatisProviders/Sources/ToolCalling.swift` 的 `AgentMessage` / `AgentChunk` 没有独立
report sidecar。初版明确复用现有 `ToolCallingProvider.stream` 发起第二次无工具请求，因此：

- 不修改 provider wire schema；
- 不要求每个 provider 实现新的 response 字段；
- 不从 UI bubble、assistant final 或任意 prose 猜测 report；
- 必须以 request-owned stream 和 exact inference binding 遵守现有 provider cancellation 合同。

### 11.5 Tests

- `Packages/IntatisCowork/Tests/PermissionReviewControlPlaneTests.swift`
- `Packages/IntatisCowork/Tests/AutomaticPermissionReviewTests.swift`
- `Packages/IntatisAgentKernel/Tests/` 下增加 reporter/context-snapshot 交界测试；
- 增加 protocol/EventLog backward-decode 与 exact-call isolation 测试。

本方案不要求修改 `TaskContract`、Orchestrator continuation 语义、Goal/WorkTask、UI、TaskGraph、
ToolRegistry、provider wire、browser executor 或其他具体工具 schema。若实现阶段发现必须修改其中任一
边界，应先停下重新评估，因为那意味着实现已经偏离“集中修改权限上下文边界”的最小目标。

## 12. 必须增加的回归测试

### 12.1 原事件复现

1. 提交完整 arXiv 任务；
2. main 完成若干 browser 步骤；
3. 注入 retryable provider interruption；
4. 用户发送 `Continue.`；
5. main 请求新的 browser ask-class action；
6. 断言同一 main exact binding 收到一次 `tools: []` report request；
7. 断言 report request 看见 main 的真实 provider-facing history 和当前 tool-call batch；
8. 断言 host 将模型句柄映射为 seq 884、2520，并建立合法 evidence closure；
9. 断言 reviewer prompt 包含原目标、进度、canonical 最新指令、当前动作理由和用户证据；
10. 断言 prompt 不再只显示两次 `Continue.`；
11. reviewer allow 后只有原 exact tool call 能继续执行。

### 12.2 单轮完整指令

独立完整请求仍应生成正确报告，不改变当前正常审查结果，也不增加重复工具执行或重复 permission
settlement。

### 12.3 范围扩大

main 报告声称用户授权上传或删除，但 supporting user events 不包含该要求时，reviewer 必须拒绝。

### 12.4 Evidence closure 与用户撤销

模型只选择较早“允许下载”的消息，但其后用户说“不要下载，只阅读摘要”时，宿主必须把中间撤销消息
自动加入 closure。report 与较新撤销冲突时 reviewer 必须拒绝下载。

### 12.5 报告生成失败

超时、provider error、空报告、malformed JSON、未知句柄、错误 exact binding、consumer cancellation
和 late output 均不得自动 allow，也不得进入 GUI 人工 fallback；当前 permission lifecycle 必须留下
durable typed deny。

### 12.6 秘密与 Prompt Injection

报告、用户证据和 action preview 中的 secret-like material 必须脱敏；伪造
`<<<END_REVIEW_TARGET>>>` 等边界文本不能突破 untrusted block。

### 12.7 Worker scoped context

worker 生成报告时只能使用自己的 task-scoped context；测试必须证明它不会获得 main 的完整对话或其他
agent 的私有上下文。worker 返回指向 main-only 用户消息的未知/越界句柄时必须拒绝。

### 12.8 Durable compatibility

旧 `PermissionReviewCausalContext` 和旧 `permission_review_requested` JSONL 在缺少新增字段时继续解码；
新 `authorizationContext` 随完整 review task 原子持久化，request/settled audit 能按既有 reviewTaskID
在重启后回放和对账，不需要额外 digest。

### 12.9 不影响现有权限分支

- deterministic allow 不新增无意义 reviewer call；
- deterministic hard deny 不触发 report 生成来尝试放宽；
- manual mode 不触发 automatic context reporter；
- automatic reviewer 仍为 FIFO/single-flight；
- cancel、timeout、late provider output 和 first-terminal CAS 行为不变。

### 12.10 Exact call 隔离

同一 assistant response 含多个 tool call 时，每个 automatic ask-class call 使用自己的 action preview、
toolCallID 和 report；不得把第一个调用的 justification 或证据 wrapper 复用给第二个调用。一个 call 的
report timeout 不得让另一个 call 获得旧报告或旧 allow。

### 12.11 Reporter 不污染数据面历史

reporter request 和原始 JSON response 不得成为 UI assistant bubble、普通 model-history message、
TaskGraph task 或 MessageBus event。只有宿主验证后的 bounded `authorizationContext` 进入当前 durable
permission review request；usage 仍按现有计量合同记录。

## 13. 完成标准

只有同时满足以下条件，才能声称修复完成：

1. reviewer 不再把当前一句 `Continue.` 当作完整授权目标；
2. 只有 automatic ask-class exact call 触发 reporter，其他 permission 分支行为不变；
3. report 确由 requesting agent 的同一 exact model binding 基于真实 provider-facing context snapshot 生成；
4. reporter 使用 `tools: []`，不进入 AgentLoop、scheduler、UI 或普通模型历史；
5. 模型只返回临时用户句柄，宿主完成 seq 映射、当前消息加入和 evidence closure；
6. reviewer prompt 明确分开 untrusted report、canonical latest instruction 和 supporting user evidence；
7. report 通过现有 review task 与 authorization snapshot 绑定 exact turn/task/toolCall/requesting agent；
8. 没有用重复 author/latest-instruction 字段或同事件 digest 代替现有结构绑定；
9. report 不能扩大 deterministic gate、capability 或 workspace ceiling；
10. 缺失、冲突、无法验证、history gap 和 secret-bearing report 均 durable fail-closed；
11. 原 `cowork_w89crmx9` 流程及一般代词/重试/范围变更回归通过；
12. 旧 EventLog 协议测试通过；
13. PermissionReviewControlPlane 和 reporter 的 timeout/cancel/late-output/durability 回归通过；
14. 全量相关 SwiftPM tests 与 macOS Developer ID 目标 Debug build 通过；
15. 项目文档同步说明新上下文合同及仍未实现的未来 continuation/UI 增强。

## 14. 明确排除的错误修法

- 只把最近 N 条完整聊天原样塞给 reviewer；
- 只识别字面值 `Continue/继续` 并自动继承任意历史任务；
- 让 reviewer 自己浏览整个 EventLog 或运行工具；
- 把 main 的报告直接视为用户授权，不附 supporting user evidence；
- 让模型直接提交 EventLog sequence、requesting agent 或 authorization identity；
- 只接受模型挑选的离散旧消息，不补齐其后的用户撤销、限制和范围变化；
- 重复持久化 latest instruction/report author，并允许副本与 canonical 字段不一致；
- 把与报告同存的 digest 当作独立真实性或授权证明；
- 从 assistant final、自由文本气泡或隐藏推理中截取 report；
- 把 report 放进每个具体工具的业务参数并交给 executor；
- 复用上一轮 reviewer allow 作为后续 blanket approval；
- 因为 report 表述合理就跳过 exact authorization、gate、lease 或 execution revalidation；
- 为减少误拒绝而把 reviewer failure 改成人工等待或默认 allow；
- 把完整网页、tool observation、cookie、token、credential 或隐藏推理放进报告。

## 15. 已确定的实施选择与剩余参数

原报告列出的主要结构问题已经收敛：

1. 当前 provider response 类型没有可靠 sidecar；使用一次同 agent、同 exact binding、`tools: []` 的
   request-owned provider call；
2. reporter 使用真实 provider-facing context snapshot 和当前 assistant tool-call batch，不读取 UI bubble；
3. 模型返回临时 user handles；宿主映射为 EventLog seq，并从最早引用到当前消息建立 evidence closure；
4. 一个 optional `authorizationContext` 只包含 typed report 和 host-validated sequences；
5. latest instruction、author 和 exact binding 使用现有 canonical 字段，不新增副本；
6. 不持久化 `bindingDigest`；继续依赖现有 review-task/authorization 结构校验和 durable event identity；
7. 初版按每个 automatic ask-class exact tool call 分别生成报告，不跨 call 缓存；
8. reporter/reviewer failure 均 fail-closed，不切换 GUI 人工 fallback；
9. 默认产品 UI 不展示 reporter 的原始请求/响应，不新增继续/恢复专用交互；
10. 不修改 provider wire、TaskContract、Orchestrator continuation、ToolRegistry 或具体工具 schema。

仍需在实现时依据当前代码与 conformance tests 确定的只是局部参数：

1. 每个 report 字段和 supporting excerpt 的具体字符/token 预算及安全截断方式；
2. report request 的具体 timeout 值，以及如何接入现有 session/turn usage meter；
3. report generation failure 使用现有哪个 typed failure kind，还是增加精确的
   `authorization_context_unavailable` 类别；
4. internal reporter helper 的最终文件名和可见性。

这些剩余项不能改变上面已确定的 provenance、scope、binding、evidence closure 或 fail-closed 语义。

## 16. 源码与证据入口

以下行号按 Mopelium 源码基线 `23678e6b452347d4aff41dc4f85fd949727ccf70` 核对；后续源码漂移时
以 symbol 和当前实现为准。

### 当前 root 与 main history

- `Packages/IntatisCowork/Sources/Orchestrator.swift:2946`
- `Packages/IntatisCowork/Sources/Orchestrator.swift:2995`
- `Packages/IntatisCowork/Sources/Orchestrator.swift:6756`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3236`

### Permission request

- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:707`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:927`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:1537`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:1647`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3146`
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift:3201`
- `Packages/IntatisProtocol/Sources/PermissionReview.swift:46`

### Reviewer control plane

- `Packages/IntatisCowork/Sources/AgentPermissionResponder.swift:10`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:602`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:619`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:629`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1139`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1217`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1320`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1360`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1380`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift:1902`

### Tool authorization

- `Packages/IntatisTools/Sources/ToolProtocol.swift:1020`
- `Packages/IntatisTools/Sources/ToolProtocol.swift:1144`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:225`
- `Packages/IntatisProtocol/Sources/ToolAuthorization.swift:570`

### Provider response shape 与 durable review

- `Packages/IntatisProviders/Sources/ToolCalling.swift:191`
- `Packages/IntatisProviders/Sources/ToolCalling.swift:369`
- `Packages/IntatisProtocol/Sources/PermissionReview.swift:280`
- `Packages/IntatisConversation/Sources/EventLog.swift:1009`

### Prior incident report

- `Codex-report/COWORK_BROWSER_PERMISSION_CONTINUATION_INCIDENT_2026-08-07.md`

## 17. 最终判断

浏览器工具当前没有被本事件证明存在新的硬性阻断；真正导致本次端到端流程停止的是自动权限 reviewer
获得了错误粒度的任务语义：main 知道完整故事，reviewer 只知道 `Continue.`。

当前敲定的修复不是让 reviewer 读取完整对话，也不是先建立复杂 continuation 系统，而是在现有
permission causal context 中增加一个 optional `authorizationContext`。对每个 automatic ask-class exact
tool call，requesting agent 的同一模型用真实上下文快照和 `tools: []` 的独立请求生成 typed report；
模型只选择临时用户证据句柄，宿主映射并补齐 evidence closure。最新用户原话、报告作者和 exact binding
继续从 EventLog、现有 requestingAgent 和现有 resolved authorization 读取，不复制字段，也不增加没有
独立信任价值的持久化 digest。

报告只解释语义，不创造授权。canonical 用户消息仍是用户依据，确定性 gate、exact authorization 和
leases 仍是不可扩大的权限上限。该方案不依赖 `Continue/继续` 等窄字符串匹配，能够覆盖代词引用、
重试、方案选择、范围扩大/撤销和 task-scoped worker 等一般情况。

这是目前能够直接修复已观察缺口、同时保持 Cowork 安全边界和架构简洁性的最小一致方案：协议表面小，
实现量中等，代码触点集中，不需要重写 TaskContract、Orchestrator、provider wire、UI 或工具执行器。
