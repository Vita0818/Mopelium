# Cowork 浏览器端到端测试与权限续跑上下文缺口事件报告

> **后续设计决策（2026-08-08）：** 本报告关于权限上下文的根因证据仍然有效；但第 6.1、7.2—7.6、
> 第 9—11 节中把 durable continuation binding 作为首要修复的方案，已被
> `COWORK_PERMISSION_REVIEW_CONTEXT_INCIDENT_AND_MINIMAL_REVISION_2026-08-08.md` 记录的最新决策取代。
> 当前优先方案是在权限审查边界引入由请求 agent 模型生成、由宿主绑定证据的
> `Authorization Context Report`，暂不先重构 task/continuation/UI 语义。

- 报告日期：2026-08-07
- 调查对象：Cowork 浏览器工具、自动权限审查与跨轮续跑
- 重点 session：`cowork_w89crmx9`
- 当前结论：浏览器 observation / pre-action no-effect 缺陷已修复并通过回归；跨 submission 的可信授权上下文续接仍未实现
- 本报告任务的修改范围：仅新增本报告，不修改业务代码、配置或既有项目文档

## 1. 执行摘要

本次事件不是单一故障，而是连续测试依次暴露出的三层问题：

1. **浏览器工具曾有真实实现缺陷。** Playwright/CDP 共用的 interactive-element extractor 在嵌套
   Swift → Node.js → page JavaScript 字符串中发生转义错误，同时调用方使用
   `.catch(() => [])` 吞掉 extractor 异常，导致页面明明有搜索框、按钮和链接，snapshot 却把它
   伪装成“没有交互控件”。目标未找到的动作前错误又被包装成普通 backend failure，最终被 durable
   execution 视为可能已经产生副作用，进入 `manual_reconciliation`。
2. **浏览器工具修复已经生效。** 修复后，snapshot 能返回可见控件的 role、accessible name、type
   和可复用 selector；固定 broker 在只读 preflight 明确证明动作尚未开始时，会返回结构化
   `effectDisposition=not_started`，AgentLoop 能把恢复信息交还模型继续执行。普通 timeout、动作后
   异常和下载等待失败仍保持保守的 unknown/manual 语义。
3. **修复后的真实流程进一步暴露了 Cowork 权限续跑缺口。** 主 agent 拥有跨轮 model history，知道
   用户输入 `Continue.` 是在继续 arXiv 测试；但自动权限 reviewer 不读取完整对话，只收到当前新
   root task 的结构化权限包，而该 task 的 objective 只有字面值 `Continue.`。因此 reviewer 面对
   `browser_type` 的高风险网络/进程动作时 fail closed，认为当前目标不足以证明调用合理并拒绝。

最终结果是：模型先生成了一份完整的失败报告，运行时随后又追加
`unresolved_denied_side_effects`、`turn_outcome=failed`、`task_failed` 和 submission failed。UI 因而
同时显示“完整回答”和“任务失败”，形成“既完成又没完成”的观感。事实上该任务只完成了浏览器工具
恢复语义、arXiv 搜索和论文定位，没有进入论文详情页，也没有调用 `browser_download`，下载目录为空。

本事件的关键未实现能力不是“让 reviewer 读取整段聊天”，而是：

> 在用户明确续跑一个可恢复任务时，由宿主从 EventLog 建立可信、可验证、不可由模型伪造的
> continuation binding，并把原始用户授权目标与本轮指令分开提供给权限 reviewer。

## 2. 产品与测试背景

Mopelium 当前不新建平行产品模式；新增能力只修饰 Cowork。网络访问目标是让 Cowork agent 通过真实
HTTP(S) 浏览器 session 获取网页、操作页面，并在登录、2FA 或秘密输入时切换到用户可操作的 headed
handoff。科研场景的工具层目标主要是：

- 真实网络访问与网页交互；
- 多种文档格式的读取。

本轮浏览器验收场景从 GitHub 下载逐步推进到 arXiv 搜索与文件下载，预期证明：

1. snapshot 能提供模型可直接复用的可访问性定位；
2. 错误定位在动作前失败时不会卡死整个 turn；
3. 多次 browser 调用复用同一 live profile/session；
4. 能通过真实网页 UI 找到论文、进入详情页、下载 TeX Source，并用 `browser_downloads` 验证落盘；
5. 每个动作仍逐次经过 ToolRegistry、lease、PermissionEngine 和 durable execution。

## 3. 事件时间线

### 3.1 修复前的连续症状

| 阶段 | 可见症状 | 当时结论 |
|---|---|---|
| GitHub `Download ZIP` 测试 | `browser_download` 在 click/evaluate 路径报错，被显示为 `manual_reconciliation` | 不能证明动作是否已经发生，框架保守停止 |
| `browser_wait` 测试 | wait timeout 同样进入 manual reconciliation | 不是模型多模态问题；backend 超时与 side-effect 语义混在一起 |
| arXiv 搜索测试 | snapshot 页面文字里有搜索表单，但模型无法获得可靠 interactive element；`browser_type` 报 element not found | observation 与 action locator 语义不一致 |
| UI 卡住/转菊花 | agent 在工具错误、provider 响应和 terminal settlement 之间长时间等待 | 需要先修工具错误分类，再区分 provider/network 与框架终态 |

### 3.2 浏览器工具根因定位

真实 CDP loopback 回归最终暴露了以下确定性根因：

- interactive extractor 是一段嵌套在 Swift 多行字符串和 Node broker 中的 page JavaScript；
- 空白归一化正则的反斜杠在嵌套层中丢失，`/\s+/` 实际变成 `/s+/`，会删掉 accessible name 中的
  字母 `s`；
- CSS 字符串转义正则在最终 page JavaScript 中成为非法正则，触发
  `SyntaxError: Invalid regular expression`；
- Playwright/CDP 两条 snapshot 路径都使用 `.catch(() => [])`，把上述真实脚本失败伪装成空控件数组；
- CDP locator 与 snapshot 对 role/name 的推断不完全一致；
- action target miss 没有明确的 host-known mutation boundary，普通 backend error 被 durable runtime
  视为副作用不确定。

### 3.3 已实施的浏览器工具修复

事件过程中已经完成但不属于本报告新增修改的修复包括：

- 移除两条 observation 路径对 interactive extractor 的静默 `.catch(() => [])`；
- 消除脆弱的嵌套反斜杠正则，改用不依赖该转义链的字符串处理；
- 用安全的 JSON/CSS identifier 生成方式替换失效的 CSS 转义表达式；
- selector 只有在唯一命中当前元素时才直接输出，否则生成有界 ancestor path 和正确
  `nth-of-type`；
- snapshot 只输出当前可见控件，并遮蔽当前输入值、密码、Token、cookie 和 profile 内容；
- 对齐 CDP snapshot 与 action locator 的 role、accessible-name、label、placeholder、title 和
  `aria-labelledby` 语义；
- Playwright/CDP action 在真正 mutation 之前执行只读 target preflight；
- 固定 broker 只对 allowlist 内的 pre-action target miss 输出：

```json
{
  "marker": "intatis_browser_backend_error_v1",
  "code": "browser_action_target_not_found",
  "effectDisposition": "not_started"
}
```

- Swift 只解析上述固定结构化 stdout marker，不匹配任意 stderr/free-text；
- 只有被证明 `not_started` 的错误转换为 `ToolExecutionRejectedWithoutSideEffect`；
- DOM race、动作调用后错误、普通 timeout、lost acknowledgement、下载未出现或其他 backend failure
  仍保持 unknown/manual reconciliation。

### 3.4 修复后的验证结果

事件过程中已经执行并通过：

- 完整 `swift test`：退出码 0；
- `IntatisToolsTests`：151 tests / 16 opt-in skipped / 0 failures；
- `ToolExecutionRejectedWithoutSideEffect` 的 AgentLoop recovery focused test：1/1；
- Microsoft Edge + loopback CDP form snapshot/locator smoke：1/1；
- dynamic feed、select/press、submit、upload/download 真实 browser smoke：4/4；
- `xcodegen generate`：通过；
- `IntatisMac` macOS Debug unsigned build：通过。

这些结果证明浏览器工具的 observation 和动作前 no-effect 修复有效，但不等于公网 arXiv 下载全过程
已经完成。

### 3.5 `cowork_w89crmx9` 的关键 EventLog 事实

session canonical truth 位于：

```text
~/Library/Application Support/Intatis/cowork_w89crmx9/events.jsonl
```

以下序号来自该 append-only EventLog：

| seq | 事件 | 结论 |
|---:|---|---|
| 884 | 新的 arXiv 端到端测试 user message | 新 submission 开始 |
| 983–994 | `browser_navigate` arXiv 首页并成功 settlement | 连续 CDP browser session 正常 |
| 1064–1065 | `browser_type` 带不支持的 `exact` 字段，schema validation 拒绝 | 测试提示词错误，不是浏览器 backend 错误 |
| 1106–1117 | 故意使用不存在的 textbox name；tool result failed，settlement 为 `not_started` | 新修复按预期生效，模型继续执行 |
| 1212–1223 | fresh `browser_snapshot` 成功 | 首页控件可被 observation 返回 |
| 2159–2170 | 使用 snapshot 中的 `textbox "Search arXiv"` 提交搜索并成功 | 真实 UI 搜索成功 |
| 2333–2344 | 点击第 3 页并成功 | 页面文字中找到目标论文 |
| 2437–2448 | 点击标题 role/name 失败，settlement 为 `not_started` | 目标当时不在可见 interactive controls 中，未产生不确定副作用 |
| 2514–2519 | provider streaming connection lost；turn/task/submission failed，retryable=true | 第一轮真正终止原因是 provider/network 中断 |
| 2520 | 用户发送 `Continue.` | 当前实现把它作为全新 submission/root task |
| 2697–2705 | 新 task 尝试 `browser_type`；automatic reviewer deny | reviewer 只看到当前 objective `Continue.`，无法证明高风险网络动作合理 |
| 3816 | 主模型完成一份约 3k 字的失败报告 | `message_completed` 只表示文本生成完成，不表示 turn 成功 |
| 3819–3824 | `unresolved_denied_side_effects`、turn/task/submission failed | runtime 最终正式判定失败 |

进一步核对得到：

- 修复后的流程没有调用 `browser_download`；
- 对应 profile 下载目录没有文件；
- browser state 最终仍停留在 arXiv 搜索结果第 3 页；
- `session.json.projectedThroughSeq` 仍为 883，而 EventLog 已到 3824；这是独立的派生投影滞后异常，
  EventLog 仍按设计是 canonical truth。

## 4. “既完成又没完成”的准确解释

该 session 同时出现两个不同层次的“完成”：

- **文本生成完成**：主模型成功生成了说明哪些步骤完成、哪里被权限阻断的报告，因此有
  `message_completed`；
- **任务执行未完成**：必要 browser side effect 被权限 reviewer 拒绝，runtime 检测到 unresolved
  denied side effect，随后把 turn、task、continuation run 和 submission 全部结算为 failed。

因此事实不是“下载任务成功但 UI 误报失败”，而是：

> 模型完整地报告了一个未完成任务；UI 没有足够清楚地区分“最终说明文本”与“成功终态”。

这属于终态表达问题，不应通过把 failed 强行改成 completed 来解决。正确做法是保留 durable failed
事实，同时把该文本标记为 partial/failure report。

## 5. 当前 Cowork 自动权限审查如何工作

### 5.1 调用链

```text
主模型提出 tool call
  → ToolRegistry schema 与 concrete registration 校验
  → CapabilityLease / WorkspaceLease / workspace identity 校验
  → DeterministicPolicyGate
  → 构造并持久化 PermissionReviewTask
  → 独立 @permission-reviewer provider call（无工具、single-flight）
  → 持久化 allow / deny settlement
  → allow 后才准备并执行真实工具
  → durable tool result / execution settlement
```

硬性 policy deny 是终局；reviewer 不能绕过 registry、lease、workspace 或 deterministic gate。每个
browser action 都重新审查，上一调用的 allow 不是后续调用的 blanket approval。

### 5.2 Reviewer 当前能看到什么

reviewer 收到的是宿主生成的有界结构化权限包，而不是主 agent 的完整 prompt：

- 当前 task/root/parent ID、attempt、assignee、issuer；
- 当前 `TaskContract.objective`、role hint、expected deliverable；
- exact tool、canonical action、side effect、network risk、replay policy；
- browser-specific `PermissionActionPreview`，例如 profile、target、clear/submit、输入字符数；
- normalized args digest/字符数，而非 browser input 的完整 value；
- touched paths、PermissionIntent resources/data/control/risks；
- deterministic gate decision/risk/reason；
- capability lease、workspace lease、workspace identity 与 authorization fingerprints；
- 当前 task lineage、related agents 和少量由 EventLog seq 指向的 causal event summaries；
- 当前 active agent roster 的有界摘要。

### 5.3 Reviewer 当前看不到什么

- 主 agent 的完整 Cowork model history；
- 任意完整聊天 transcript；
- 上一 submission 的原始目标，除非它被结构化连接进当前 task causality；
- 上一轮主模型的推理或完整 observation；
- 浏览器画面、网页正文、cookie、localStorage、profile database；
- 密码、2FA、Token 或 `browser_type` 的实际输入值；
- 任意工作区文件内容；
- 自主查日志或浏览器的工具能力。

### 5.4 本次 reviewer 实际收到的关键事实

本次 permission request 的有效语义可概括为：

```text
current task objective: "Continue."
current task kind: new root task
tool: browser_type / browser.type
target: textbox:Search term or terms
input_characters: 41
clear: true
submit: true
risks: network_access + process_execution
workspace/capability leases: present
previous arXiv root task and original user instruction: not in current lineage
```

在这份证据下 reviewer 的 deny 符合 fail-closed 规则。问题不在 reviewer “不够聪明”，而在宿主没有
为真实 continuation 提供足以证明授权关系的结构化事实。

## 6. 本次发现缺少的能力

### 6.1 核心缺口：跨 submission 的可信 continuation binding

当前每次 composer Send 都创建新的 root `TaskContract`，objective 直接使用本轮文本。`Continue.` 因此
成为新 root 的完整目标；它没有 parent task，也没有指向前一失败 submission/root task 的可信字段。

主 agent 能从 model history 理解自然语言连续性，但权限 reviewer 不能把模型理解当作授权事实。这使
两条链路发生分叉：

- data plane 知道“继续 arXiv”；
- control plane 只知道“Continue.”。

### 6.2 当前指令与授权目标没有分离

现有结构把 `TaskContract.objective` 同时当作：

- 当前用户本轮说的话；
- reviewer 判断工具是否获得用户授权的唯一目标。

对独立完整指令这通常成立；对“继续、重试、接着做”不成立。系统需要同时保存：

- `currentInstruction`：本轮用户的增量指令；
- `authorizationGoal`：由原始 user message 提供、可从 EventLog 验证的授权依据。

### 6.3 缺少明确的续跑用户动作

UI 目前允许用户直接发送 `Continue.`，但没有稳定地表达“继续哪个 task/submission”。模型可以猜，
权限层不能猜。需要用户可见的 `Retry same task` / `Continue from saved state` 动作，或者在唯一可恢复
候选存在时显示明确绑定确认。

### 6.4 缺少终态与说明文本的明确区分

`message_completed` 先于最终 runtime terminal event 合法发生，但 UI 不应让完整的 failure report 看起来
像 task success。需要清晰表达：

- assistant report produced；
- task outcome failed/partial；
- blocker 是 provider、permission、policy、sandbox 还是 runtime。

### 6.5 派生 `session.json` 没有及时追上 EventLog

该 session 的投影停在新测试开始前。按架构 EventLog 胜出，因此没有 canonical data loss；但长期滞后
会影响 history/session summary、恢复与多窗口一致性，需要单独定位 projection refresh 或落盘失败路径。

### 6.6 测试提示词与真实工具合同不一致

本轮提示词有两个明确问题：

- 要求 `browser_type exact=true`，但该工具 schema 没有 `exact` 字段；
- 限制只能使用六个工具，排除了 `browser_scroll`。目标论文位于视口以下，page text 可见但
  interactive controls 只按合同输出可见元素，模型无法合规地把目标滚入可操作范围。

这两点应修正测试设计，但它们不能解释或替代权限 continuation 缺口。

## 7. 推荐设计

### 7.1 设计原则

1. 不把完整聊天历史交给权限 reviewer；
2. 不信任主模型生成的“用户已经授权”摘要；
3. 只从 EventLog 中的原始 user message 和宿主验证过的 task/submission 关系建立授权依据；
4. continuation 只继承原任务范围，不继承 blanket tool approval；
5. 每个 exact tool call 仍重新经过 gate、lease 和 reviewer；
6. workspace、identity、lease、trust domain 或任务范围改变时继续 fail closed；
7. 所有新协议字段 additive/optional，旧 JSONL 必须继续解码。

### 7.2 新增持久 continuation 结构

建议引入等价于以下语义的结构，名称可在实现阶段校准：

```text
TaskContinuationBinding
  previousSubmissionID
  previousRootTaskID
  originalUserMessageSeq
  originalGoalDigest
  mode: retry | resume | follow_up
```

关键要求：

- binding 由宿主建立，不能由模型提供；
- original user event 必须存在于同一 session EventLog；
- seq、SubmissionID、TaskID、goal digest 必须相互验证；
- continuation binding 与新的 `user_message + queued` 在同一持久化事务边界内冻结；
- 新 turn 可继续使用新的 TaskID，保证每轮 terminal 唯一，但必须保留 causal link；
- 不应借 continuation 自动复制或扩大 capability/workspace lease。

### 7.3 建立 continuation 的条件

仅在以下条件成立时绑定：

- 同一 Cowork session；
- 目标是唯一、最近且明确可恢复的 prior submission/root task；
- prior terminal 是 provider interruption、retryable runtime failure、paused 或其他明确允许 resume 的状态；
- prior task 不是 user-cancelled、hard-policy-denied 或明确手动拒绝后禁止继续的任务；
- workspace canonical identity 和必要 agent identity 可验证；
- 用户通过明确 UI action，或在只有一个无歧义候选时确认确定性的续跑命令。

存在多个候选、没有候选或 identity 无法验证时必须要求用户选择/重述，不得让模型猜。

### 7.4 扩展权限 causal context

建议将 current instruction 与 authorization basis 分开：

```text
PermissionReviewCausalContext
  currentInstruction
  authorizationGoal
  authorizationSourceEventSeq
  continuationOfSubmissionID
  continuationOfTaskID
  continuationMode
  previousTerminalSummary
  currentTaskLineage
  authorizationLineage
  eventSequenceNumbers
```

reviewer prompt 应明确显示：

```text
current_instruction: "Continue."
authorization_goal: "从 arXiv 首页搜索指定论文并下载 TeX Source"
authorization_source_seq: 884
continuation_of_task: <prior root task>
previous_terminal: provider_failed / retryable
```

原始 goal 应由 host 从 exact EventLog seq 读取、限长、清洗并标记为 untrusted quoted data。不要复制整段
assistant transcript，也不要用 assistant summary 代替 user authorization。

### 7.5 把授权依据绑定进 resolved authorization

当前 resolved authorization 已绑定 task objective、tool、args digest、lease fingerprints、workspace
identity 等事实。continuation 实现还应加入：

- authorization source event seq；
- original goal digest；
- continuation binding digest/revision。

permission request、review settlement、tool prepare 和最终 execution revalidation 必须验证同一个
authorization-context fingerprint，防止等待期间 task/goal/lease 被替换。

### 7.6 UI 与提交语义

在 retryable failure、paused 或 interrupted 状态下提供：

- `Retry same task`：重试同一 submission/task attempt 语义；
- `Continue from saved state`：创建新 turn/task，但携带明确 continuation binding。

若用户手工输入“继续”，只有一个符合条件的 prior task 时，UI 应在发送前显示：

```text
将继续：arXiv 论文搜索与 TeX Source 下载
```

用户确认后再冻结 binding。若消息同时加入新要求，reviewer 应分别看到原授权目标与当前增量；旧目标
不能授权新增范围。

### 7.7 终态呈现

保留 runtime 的真实 failed terminal，不把 failure report 伪装成 success。UI 应将组合状态表达为：

```text
Partial report produced
Task failed: permission denied / provider interrupted / runtime failed
```

同一 turn 中的 final assistant text、tool outcome、turn outcome 和 task outcome 应关联展示，避免用户把
`message_completed` 理解为业务完成。

### 7.8 修复 `session.json` 追赶

单独审计 SessionProjectionStore / session summary refresh：

- terminal settlement 后必须尝试从 EventLog 更新派生投影；
- 若 projection 写入失败，应有可见但脱敏的 durable diagnostic；
- 冷启动必须检测 `projectedThroughSeq < EventLog latest seq` 并 rebuild；
- 不得为了追赶而覆盖未知 future event 或伪造 terminal；
- EventLog 始终保持 canonical truth。

## 8. 明确不推荐的修法

- 把最近 N 轮完整聊天直接附给 reviewer；
- 把网页 observation、assistant reasoning 或 raw tool args 原样放入 reviewer prompt；
- 让主 agent 自己声明 continuation 或用户授权；
- 只按自由文本“Continue/继续”自动继承任意历史任务；
- 将上一轮 reviewer allow 复用为永久权限；
- 在 workspace、lease、agent、provider trust domain 变化时静默继承；
- 为了减少误拒绝而弱化 deterministic gate、CapabilityLease、WorkspaceLease 或 durable settlement；
- 把失败任务的完整说明文本存在当成 success terminal；
- 通过自由文本匹配把普通 browser error 标成 `not_started`。

## 9. 推荐实现顺序

### P0：可信 continuation 与权限上下文

1. 定义 additive continuation binding 协议与 EventLog 编解码；
2. 在 submission admission 中验证并原子冻结 binding；
3. 在 TaskContract/任务 metadata 中保留 prior submission/root task causal reference；
4. 扩展 PermissionReviewCausalContext 与 reviewer prompt；
5. 将 authorization context digest 纳入 request/settlement/execution revalidation；
6. 确保 hard deny、cancel 和 identity mismatch 继续 fail closed。

### P1：用户操作与终态可视化

1. 增加 Retry / Continue from saved state 明确入口；
2. 对手工“继续”提供绑定确认；
3. 区分 final report 与 task success；
4. 展示 typed failure source，但不泄露 raw args/secret。

### P1：派生投影追赶

1. 复现 `projectedThroughSeq` 停滞；
2. 修复 runtime terminal 后的 projection refresh；
3. 增加冷启动 rebuild 和多窗口一致性回归。

### P2：端到端浏览器测试重写

1. 移除 `browser_type.exact`；
2. 允许 `browser_scroll`；
3. 用 latest snapshot 的 visible selector/role+name 操作；
4. title/ID link 位于视口外时先 scroll 后 fresh snapshot；
5. 进入 abstract 页后直接以最新 snapshot 中的 `TeX Source` 调用 `browser_download`；
6. 用 `browser_downloads` 验证 relative path、filename 和 size > 0。

## 10. 必须增加的回归测试

| 用例 | 预期结果 |
|---|---|
| provider retryable failure 后点击 Continue from saved state | reviewer 同时看到原始 goal 与当前 continuation 指令 |
| 同场景下一次 exact browser call | 仍逐次审查，但不会仅因 objective=`Continue.` 误拒绝 |
| 没有可恢复任务时发送 `Continue.` | fail closed，不继承旧授权 |
| 存在多个可恢复任务 | 不自动选择，要求用户确认 |
| prior task 被用户取消 | 不允许继承 |
| prior task 被 hard policy deny | 不允许通过 continuation 绕过 |
| prior workspace identity 改变 | binding validation 失败或重新要求明确授权 |
| current instruction 扩大目标范围 | 原始 goal 不能授权新增范围 |
| continuation 等待期间 lease/goal/binding 改变 | authorization fingerprint mismatch，fail closed |
| App 重启后 resume | exact binding 可从 EventLog replay，旧 JSONL 仍可解码 |
| reviewer prompt privacy | 无完整 transcript、raw browser value、cookie、Token 或网页正文 |
| pre-action target miss | `failed + not_started`，模型可 fresh snapshot 后继续 |
| post-action timeout/DOM race | 不得误标 `not_started`，继续 manual reconciliation |
| message report 后 runtime failed | UI 显示 partial report + failed terminal，不显示成功 |
| terminal 后 session projection | `projectedThroughSeq` 追到 canonical EventLog latest seq |
| 真实 arXiv flow | scroll、详情页、TeX Source 下载和 downloads metadata 全部完成 |

## 11. 完成标准

只有同时满足以下条件，才能认为本事件完全关闭：

1. browser snapshot 与 action locator 的既有修复持续通过；
2. 显式 continuation 具有 durable、host-validated prior-task binding；
3. 主 agent 与 permission reviewer 对“授权依据”看到同一份原始用户目标；
4. reviewer 仍不接收完整聊天历史或 raw secret-bearing arguments；
5. 无 continuation、歧义 continuation、cancel/hard-deny continuation 继续 fail closed；
6. final report 与 runtime terminal 在 UI 中不会被混淆；
7. session projection 能在 terminal/restart 后追上 EventLog；
8. 新的 arXiv 公网端到端测试真实完成详情页进入、TeX Source 下载和文件 metadata 验证；
9. 完整 SwiftPM tests、相关 focused tests、真实 loopback browser smoke 和 macOS Debug build 通过；
10. 旧 EventLog/schema 兼容回归通过。

## 12. 证据与相关源码入口

### 浏览器工具

- `Packages/IntatisTools/Sources/BrowserTools.swift`
  - 结构化 no-effect 解析约在 line 580；
  - Playwright broker error marker 约在 line 1403；
  - CDP broker error marker 约在 line 2218；
  - backend settlement 转换约在 line 3768。
- `Packages/IntatisTools/Tests/IntatisToolsTests.swift`
  - target miss/no-effect 对照约在 line 1805；
  - real CDP interactive snapshot 回归约在 line 2006。

### 当前 root task 与权限上下文

- `Packages/IntatisCowork/Sources/Orchestrator.swift`
  - `admitNextMainRootTask` 为每次新 Send 创建 root contract；
  - objective 直接来自当前 composer text，约在 line 2995。
- `Packages/IntatisAgentKernel/Sources/AgentLoop.swift`
  - resolved authorization 的 `taskObjective` 来自当前 contract，约在 line 1789；
  - `PermissionReviewCausalContext.userGoal` 来自当前 contract objective，约在 line 3201。
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift`
  - review task 构造约在 line 1139；
  - causal context 派生约在 line 1326；
  - reviewer prompt 约在 line 1380；
  - bounded recent causal event summary 约在 line 1902；
  - task-related event filter 约在 line 2035。
- `Packages/IntatisProtocol/Sources/PermissionReview.swift`
  - `PermissionReviewCausalContext` 与 `PermissionReviewTask` 协议定义。

### Session 证据

- `~/Library/Application Support/Intatis/cowork_w89crmx9/events.jsonl`：canonical 事件事实；
- `~/Library/Application Support/Intatis/cowork_w89crmx9/session.json`：派生投影，调查时只到 seq 883。

## 13. 风险判断

当前缺陷主要导致**错误拒绝与任务连续性中断**，不是已发现的越权放行：

- 正面：权限 reviewer 缺少授权证据时 fail closed，未执行未经证明的网络动作；
- 负面：用户和主 agent 都明确知道任务上下文，control plane 却丢失授权连续性，使正常的 Cowork
  workflow 无法可靠续跑；
- 次生风险：如果为了修复误拒绝而直接给 reviewer 完整 transcript，反而可能引入网页 prompt
  injection、隐私泄漏、陈旧指令误授权和上下文成本问题。

因此优先级应视为 Cowork 核心可靠性 P0，但修复必须保持 fail-closed 和最小披露。

## 14. 尚待确认

- 产品是否只允许显式 UI Retry/Resume 建立 continuation，还是也支持确定性识别裸
  `Continue.` / `继续`；建议至少提供 UI 明确入口，自然语言只能在唯一候选下经用户确认。
- `session.json` 投影停滞的精确触发路径尚未定位；需要单独复现和源码追踪。
- arXiv 结果页 title link 缺失究竟完全来自当前视口/visible 约束，还是 links 去重还需要额外 model-facing
  metadata 改进；现有证据至少证明测试必须允许 scroll + fresh snapshot。
- 公网 arXiv TeX Source 的最终下载仍未通过当前 App 全流程验证。
- 本报告未对 provider streaming 中断做供应商侧根因分析；现有证据只证明该轮连接丢失且 runtime
  正确标记 retryable。

## 15. 下一步建议

在继续公网浏览器测试前，先由用户确认本报告提出的 continuation authorization 设计边界。确认后按
P0 顺序实现协议、admission、permission causal context 和 authorization fingerprint，再补 UI 与终态
呈现；最后使用修正后的 arXiv prompt 做完整回归。不要继续用裸 `Continue.` 作为高风险工具续跑的
唯一授权依据，也不要用完整聊天历史绕过结构化设计。
