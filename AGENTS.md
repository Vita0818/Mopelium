# Mopelium（Intatis 来源快照）项目常驻上下文

## 外部依赖优先与禁止功能兜底（Vitemis 强制规则）

本项目继承 `/Users/vita/Vitemis/docs/DEPENDENCY_POLICY.md`。本节是强制约束，不是建议。

- 当用户指定、仓库已经采用，或经许可证、provenance、安全与平台审查可采用的外部依赖提供同等能力时，必须直接集成该依赖的官方 API 或官方扩展点。
- 不得自行重写同等能力，不得新增替代 adapter、shim、compatibility layer、wrapper、proxy、facade、协议翻译层、parallel backend、preview backend、shadow implementation 或“先兜底、以后再换”的实现。
- 本地代码只允许保留官方 API 必需的最薄生命周期、类型、权限、配置和 bundle 接线；不得重新实现、解释、扩展或替代依赖的核心能力。
- exact 依赖因版本、构建、签名、许可证、平台、安全或官方 API 限制无法接入时，必须停止该能力、明确失败、报告 blocker 并请求用户决定；不得静默降级、切换 legacy/另一 provider/backend、使用 cache/mock/简化路径或继续交付不完整替代实现。
- 现有 fallback、adapter 或重复实现不构成先例，后续不得扩展。安全 fail-closed 与明确要求的旧数据解码/迁移不是功能兜底，但必须保持最窄范围，不能演化成备用产品实现。
- 只有用户针对 exact 依赖、exact 范围和退出条件作出的新明文决定才能例外。

本文件继承 `/Users/vita/Vitemis/AGENTS.md` 中的 Vitemis 通用 Agent 规则。若本文件与通用规则冲突，在不违反系统和用户指令的前提下，以更具体、更严格的规则为准。

本文是 AI Agent 每轮进入本仓库时的入口文件。仓库根目录以 `SNAPSHOT.md` 固定的 Intatis 来源快照为 provenance 基线，当前活动源码已经原位迁移为 Mopelium；不存在需要仿照或同步的嵌套快照。执行任何代码修改、配置修改、构建脚本修改或测试源码修改之前，必须先按顺序阅读并核对下列文档：

0. `/Users/vita/Vitemis/AGENTS.md`
1. `SNAPSHOT.md`
2. `docs/MOPELIUM_PRODUCT_DIRECTION.md`
3. `docs/VERSIONING.md`
4. `docs/CURRENT_STATE.md`
5. `docs/MACOS_DISTRIBUTION.md`
6. `docs/PROJECT_MAP.md`
7. `docs/ARCHITECTURE.md`
8. `docs/DO_NOT_BREAK.md`
9. `docs/OPEN_SOURCE_REUSE.md`
10. `docs/TESTING.md`
11. `docs/NEXT_TARGET.md`（如果存在）
12. `docs/COWORK_PRINCIPLES.md`（修改 Cowork / AgentKernel / MessageBus / 权限 / agent 编排前必读）
13. `docs/AI_PROVIDER_MODEL_CONFIGURATION.md`（修改 provider/model/variant 或凭据配置时必读）

如果文档与源码、工程配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中明确指出冲突位置和采用源码为准的原因。

> 仓内现有 `docs/COWORK_AGENT_ARCHITECTURE.md` / `COWORK_TASK_CONTEXT_MODEL.md` / `COWORK_CURRENT_FINDINGS.md` / `COWORK_MIGRATION_PLAN.md` / `COWORK_AGENT_INVOCATION_MODEL.md` / `COWORK_V0_10_SMOKE.md` / `COWORK_V0_10_STATUS.md` 是 Cowork 设计文档与状态记录，可作为深入参考；`docs/COWORK_PRINCIPLES.md` 是其原则提炼。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
```

要求：

- `pwd` 与 `git rev-parse --show-toplevel` 必须同时是 `/Users/vita/Vitemis/Virgo/Mopelium`。
- 若 `pwd` 或 Git root 不符合上述精确路径，停止修改，只报告路径问题。
- 读取 `git status --short` 后，先区分用户已有改动与本轮计划改动；不得覆盖、回退或清理用户已有改动。
- `/Users/vita/Vitemis/Intatis` 只是在 `SNAPSHOT.md` 中固定的来源仓库，不是后续默认写入目标；不得把修改写回来源或在两处隐式同步。

## Mopelium 产品方向与文档边界

`docs/MOPELIUM_PRODUCT_DIRECTION.md` 是当前产品方向的权威说明：

- Mopelium 是当前 package、target、模块、类型、Bundle ID、命令、配置键、存储路径和新协议输出的 canonical identity；
- 所有新增 Mopelium 产品功能只在 Cowork 内建设，不新增平行模式或后端；
- Chat 与 Code 保留现有代码、数据兼容和测试，但不作为当前 macOS 可见入口；唯一 App 产品是 macOS `MopeliumMac`，不提供 iOS 或 Mac App Store target。

快照自带文档继续说明当前源码事实。`docs/AI_PROVIDER_MODEL_CONFIGURATION.md` 是 AI 配置操作合同；
`docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md` 已是历史审计，不再提供迁移计划。若历史文档与当前源码、
构建配置或产品方向冲突，以源码/配置和 `MOPELIUM_PRODUCT_DIRECTION.md` 为准。

## 修改边界

本仓库是 Apple-first、Swift-native 优先的本地 AI 工作区（Swift 多 target，SwiftPM + XcodeGen），保留 Chat（普通多模态对话）/ Code（单 agent 本地工作区）/ Cowork（多 agent 本地工作区协作）三套源码能力。唯一 App 产品是全量 macOS；不提供 iOS App。允许按 `docs/OPEN_SOURCE_REUSE.md` 选择性复用兼容许可证的公开源码；当前实现是否实际包含上游代码以 `NOTICE.md` 为准。

上述三个产品面是当前源码事实，不是未来 Mopelium 信息架构。产品新增能力只能进入 Cowork；
不得为 Mopelium 复制 AgentKernel、EventLog、scheduler、permission、session runtime 或工具链。
当前内部 identity 以 Mopelium 为准；不得在迁移外复制 runtime，也不得重新引入散落的 Intatis 新写入。

macOS 只通过 Developer ID 签名、公证和直接下载分发；不做 Mac App Store
版本，源码中也不保留 App Store target/entitlements/编译分支。此决定不弱化 Mopelium 自有权限链、Workspace confinement、managed-terminal Seatbelt、Hardened Runtime 或签名/公证；精确合同见 `docs/MACOS_DISTRIBUTION.md`。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Apps/`（MopeliumMac / mopelium-cli）
- `Packages/`（当前 15 个公共库、3 个内部 C/guard target、开发期 MCP
  conformance executable 及其 Tests；精确清单以 `Package.swift` 为准）
- `Package.swift`
- `project.yml`
- `Makefile`
- `NOTICE.md`

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。当前第三方依赖与
  vendored 派生源码以 `NOTICE.md`、`ThirdPartyNotices/` 和
  `docs/OPEN_SOURCE_REUSE.md` 为准；任何新增或升级都须先过许可证与 provenance 审查。
- 不把密钥、token、证书私钥、shared secret、账号密码、完整指纹、完整 API 响应、完整转写文本或个人隐私路径写入文档。
- 不把 legacy Intatis decoder/migrator 扩成平行写入；canonical 值存在但非法时不得回退旧值，历史 EventLog 不得字符串重写。
- 不把 Mopelium 实现为与 Cowork 并列的新模式或平行 runtime；不删除 Chat/Code，也不在未获明确授权时隐藏它们。
- 不绕过 3 层权限门（DeterministicPolicyGate / ModelPermissionReviewer / PermissionEngine）、PathConfinement 工作区边界、SecretScanner、Mediator 秘密拦截或 Keychain 凭据隔离。
- 不把 Cowork 实现为硬编码递归 agent 树（main/coordinator/worker/leaf 永久角色）；遵循 `docs/COWORK_PRINCIPLES.md`。
- 不让 `AgentLoop` 直接同步递归调用另一个 `AgentLoop`；用 mailbox / scheduler / event flow。
- 不让 worker 默认获得 coordinator 工具（spawn_agent / remove_agent / delegate_task）；能力须经 `CapabilityLease` 显式授予。
- 不使用泄露/私有源码或 prompt，不复制第三方产品名称、Logo、图标、截图、UI 资产、商标性外观或品牌文案。兼容许可证的公开源码、公开 model-facing prompt 和测试可以选择性复制、翻译或修改，但必须先固定上游 commit、核对文件/依赖许可证、记录 provenance、更新 `NOTICE.md`，并遵守 `docs/OPEN_SOURCE_REUSE.md`；不得把派生实现错误标成独立原创。
- 不让复用的外部源码、依赖或 runtime 绕过 PermissionEngine、CapabilityLease、WorkspaceLease、PathConfinement、SecretScanner、Mediator、durable tool execution 或 EventLog；Apple 平台继续以 Swift 原生为主。
- 不把事件日志 JSONL schema、Envelope 格式、`seq` 单调性、ArtifactStore 索引格式当作一次性内部细节随意改动。

## 项目理解要求

修改前至少确认：

- 入口：`Apps/MopeliumMac/Sources/MopeliumMacApp.swift`（`@main struct MopeliumMacApp`，全量 macOS）与 `Apps/mopelium-cli/Sources/MopeliumCLI.swift`（CLI）。
- Chat 链路：`ChatViewModel` → `GoalInputParser`（行首 `/goal` 只生成可选 Goal 元数据，provider 收到清洗后的文本）→ `ChatLoop`（无工具）→ `EventLog`(JSONL append-only) → `ConversationProjection`。
- Code 链路：`CodeViewModel` → `GoalInputParser` → 共享 headless `AgentRuntime.code` → `AgentLoop`（maxIterations 50）→ `ContextBuilder` + `RuntimeEnvironmentManifest` → `OpenAIWireProvider` → `runTool` → `PermissionEngine`（3 层门）→ `EventLog` → `CodeProjection`。
- Cowork 链路：`CoworkViewModel` → `GoalInputParser` + `CoworkMentionRouter` → `SubmittedIntentStore`（outbox → 原子 `user_message + queued`）→ `Orchestrator.runtime`（先取得 session writer lease）→ FIFO scheduler → 共享 headless `AgentRuntime.cowork` → `AgentLoop` → `PermissionEngine` → durable tool execution ticket → executor → `EventLog`；`MessageBus` → `Mediator`。fresh Cowork 在任何模型请求前，以同一原子 7-event batch 登记完整 session settings、`@main` 与 `@permission-reviewer` 各自的 workspace/capability lease 和 identity；两者共享 canonical workspace，但 exact inference binding 分别由 main/session selection 与顶层 `permission_reviewer_model` 决定，identity/lease 也独立，reviewer 为 read_only、空工具/通信/委派且 depth 0。`permission_reviewer_model` 只接受已配置的 `<provider>/<model-id>` base profile，不增加 UI；字段缺失时仅在配置解析层一次性继承同一 JSON 文档的顶层 `model`，兼容来源缺失/未知、显式空值、错误类型、不可解析 route 或已选配置整体损坏/不可读必须让 reviewer fail closed，不能回退 UI/session default、live/historical `@main` 或其后续 rebind。GoalVerifier 继续冻结首个可解析的 exact `@main` binding，与 reviewer 配置互不替代。GUI/CLI 默认启用该保留控制面 agent，`AgentPermissionResponder` 把结构化 `PermissionReviewTask` 交给独立 `PermissionReviewControlPlane` FIFO/single-flight；reviewer 有独立 timeout/cancel 与可选 soft token warning，不占普通 scheduler 槽，只返回 `allow` / `deny`。reviewer 默认不得注入 `temperature`、output-token 或字符上限；只有用户/host 显式策略或真实上游/上下文约束存在时才可传递相应控制。request/settled 均先落 EventLog，allow 只有 settled 成功后生效；pre-submit caller cancel 直接返回 typed deny、不创建 review lifecycle；timeout、malformed、provider/persistence failure 和已登记 review 在 terminal-claim 前被观察到的 cancel durable deny 当前调用，不转 GUI 人工等待；claim 后 cancel 保留唯一 settlement 但最终 authorization delivery deny。每个 provider dispatch 都使用 exact `{reviewTaskID, nonce}` generation；provider/timeout 竞争同代首 terminal，caller cancel 由同步 request token、actor path 与下游围栏共同处理。production 按冻结 reviewer exact binding 逐代 fresh-resolve provider wrapper；timeout/cancel 只影响当前 call，若已有 active generation 就只 retire 该代，late/duplicate output 无权影响新代或执行工具。`ToolCallingProvider.stream` 必须立即返回 request-owned stream，并传播 consumer termination；不得用 `Task.detached` 宣称支持同步永久阻塞实现。旧 `provider_still_stopping` 只保留 legacy decode。Phase A 后 GUI composer 始终可编辑，Send 先冻结并持久化本地提交；reviewer 未就绪只显示状态并使后续 ask-class tool fail closed，不阻止普通主请求。CLI `/auto` 重启，只有用户明确 `/default` 才进入人工模式。审查者不得作为普通 send/delegate/message/ask 目标，不得运行嵌套 `AgentLoop`。
- Cowork automatic 的 request-owned provider-facing business schema 增加 required string `__mopelium_authorization_context`；任何 `strict:true` function 的 decorated copy 必须递归满足 `required == properties.keys` 与 `additionalProperties:false`，上述 strict object 不变量违规必须在发网前 typed fail closed。`tool_search` 本身保持原样，但其 request-owned `tool_search_output` 中延迟发现的 function/namespace 子工具也必须装饰；durable output 不变。原 ToolDescriptor/business required/executor schema 不变；宿主仅在 deterministic gate 实际进入 automatic ask 时消费并验证该字段，deterministic allow/deny 忽略其语义。acting model 在原 business function call/generation 内用这一句话说明“为什么这个 exact action 服务当前任务”，不得复制全文、声明风险或自行给出权限结论；不再有第二次 acting-model Reporter 请求。宿主先剥离 sidecar，再用 stripped canonical business arguments 做原 schema、gate、authorization、durable history 与执行。live reviewer 只收到 complete safe business arguments、complete same-generation sidecar 和 mechanical host binding/gate/lease/action facts；不得发送 TaskContract objective/role/deliverable、causal userGoal、用户消息、assistant history、PDF 或图片原文。valid sidecar 只在当前 turn 的 acting-model 内存 conversation 中保留为正确格式示例，raw sidecar 与 transient exact-args 不进入 EventLog/permission lifecycle，durable history 仍只保存 stripped business call。missing/malformed/secret-bearing sidecar 是可纠正的 acting-model tool-input failure：只写 failed/runtimeFailed `tool_result`，不创建 `permission_request` / `permission_resolved`、不调用 reviewer、也不消耗 permission denial fuse；同 business args 修正后仍可进入 reviewer。binding/authorization snapshot 无法证明则另行 typed fail closed。manual/nonautomatic 模式出现保留字段必须在业务执行前拒绝。automatic responder 必须实现 bound-invocation overload，live cached/duplicate request 必须复验 exact transient invocation，recovered allow 不得重新交付；唯一无 acting-model sidecar 的 automatic `agent.attach` 必须走 dedicated host-admission entry，并核对 exact admission identity 与先行 durable events。Cowork 若误注入 in-engine reviewer，control-plane 前必须 fail closed；shipping 默认不得这样配置。reviewer 无工具，只接受短 reason + final-line ASCII `ALLOW` / `DENY`；对 live bound invocation，reviewer reason 与 provider diagnostic 不得进入 durable lifecycle/tool-result，改用固定宿主文案。旧 Reporter context/type 仅保留 legacy decode/reconciliation，不得恢复第二次 acting-model dispatch。acting model 仍可能在普通 assistant 文本中自行复述 sidecar，该普通文本按既有消息规则持久化；malformed acting-provider error preview 仍依赖通用 bounded/secret sanitizer。live 路径也没有固定 sidecar byte ceiling 或 `review_input_too_large` admission，未来上限只能由真实 route budget 推导，不得把这些后续能力写成当前事实。
- Cowork run/mailbox 终态：只有 exact `@main` root 可见 `finish_run` / `stop_run`，模型只给 reason，所有 identity 由宿主绑定；close intent 先成为 in-process admission tombstone，EventLog first-write claim 必须先于既有 admission 等待与 exact-run drain 落盘，user/runtime/host-lifecycle source 保真，恢复时不得复活，普通 final 不伪造显式 claim。mailbox 按 authority class 收窄：ordinary message one-way/no ACK，information request 只允许一个 exact `reply_message(inReplyTo:)` terminal，information reply receipt 不得再 reply/ACK；确需继续时用 fresh `request_information(based_on: reply MessageID)`，保留 conversation root。因此 `information_replied` 只终结当前 correlation，不得成为长期协作的全局回复禁令。
- Code/Cowork 的 model-facing 因果合同：同一 assistant response 的 multi-call batch 既不是 transaction，也不是 concurrency request/guarantee，只能包含互相独立且对任意 host execution order 都正确的 calls；任何 identity/ID/attachment/state 依赖必须等待前置调用成功 `ToolResult` 后在下一 tool-call round 使用，planned/future object 不得冒充已存在。WorkTask 是当前 Cowork Session 内的独立记录，不含 Run、Goal、Agent 或 Turn owner；`task_create` 不分配 agent。`delegate_task` 只能使用已经 attached 的 data-plane agent，省略 target 时也只选择现有 idle worker；需要新 agent 时必须先独立 `spawn_agent` 并等待成功 ToolResult。production `task_create` / `task_update` 只有首个 WorkTask EventLog append 前的 Orchestrator preflight rejection 可 typed `not_started`；append/persistence/lost-ack 仍是 unknown/manual，不得按错误字符串或 `MopeliumError` case 全局推断安全重试。内部 delegation 必须先完成 preflight/Mediator，再以一个 EventLog batch 提交 message、delegation、lease、invocation、queue 与 WorkTask linkage；batch 前拒绝不得留下部分事实。
- 权限 3 层：`DeterministicPolicyGate`（纯函数、模型无关、deny 终局；普通写入/网络/exec 进入 ask 流）→ `ModelPermissionReviewer`（只能收窄 gate `pass`，不能放行 hard deny）→ `PermissionEngine`（`askUser` 交给当前 `PermissionResponder`；Cowork 自动模式只接受 control-plane allow/deny，人工模式须由用户显式切换）。
- Phase C 权限/turn 合同：每个新 Chat/Code/Cowork turn 使用稳定 `TurnID` 并追加唯一语义的 `turn_outcome`；权限请求携带 turn/tool-call/authorization correlation 与 manual/automatic mode。`EventLog.registerPermissionRequest` 对同一 RequestID first-write-wins，`settlePermissionRequest` 在 complete-known history 与跨进程锁内执行 first-terminal CAS：exact duplicate 幂等，冲突 payload/terminal fail closed。人工 `Decline Call` 只写当前 call 的 typed denied `tool_result` 并允许模型继续；`Cancel Turn` 写 permission terminal 后中断整个 turn，禁止伪造 denied tool result。user/policy/reviewer/sandbox/runtime/cancel 必须保留 typed source；明确的 sandbox wrapper startup denial 结算为 `sandbox_denied/not_started` 且不自动 retry，普通 nonzero/EPERM 不得误分类。权限投影保持 FIFO，重显复用同一 RequestID，任意一项终结不得重排其余项；取消/终止必须先 drain tool/provider 清理，再写 task/turn terminal 并恢复 caller。
- Phase L 应用生命周期：macOS 的 Chat/Code/Cowork runtime 由进程级 `AppSessionRuntimeManager` 按 exact `{SessionKind, SessionID}` 持有，窗口只持有当前展示选择；切换 mode/session、Command-W 或关闭最后窗口不得隐式 stop。删除 session 必须先精确 drain 对应 runtime，其他窗口收到 removal 后退出已删除详情。Command-Q 先关闭新操作 admission，再同时广播所有 runtime stop，并在有界 deadline 后允许进程退出；超时不伪造 settled。冷启动只 replay/reconcile：历史 active Goal durable 转为 paused（达到预算则 budget-limited），历史 running/stopping 由既有恢复路径显示 interrupted，不自动调用 provider；只有明确 Retry、Resume、Send 或 CLI `/auto|/default` 后的显式 data-plane 动作才可继续。Chat/Code/Cowork shutdown 均须取消并等待本 runtime 已登记的 provider/tool/operation task，再释放权限 waiter、subscription 与 workspace scope。
- 平台边界：当前没有 iOS App target；`PlatformProfile.current` 仍默认 `.iOS` 作为忘记设置时的最受限能力信封，shipping `MopeliumMac` 必须显式选择 `.macDeveloperID`。
- macOS 分发边界：唯一发行 App 是 Developer ID/direct-distribution
  `MopeliumMac`，Bundle ID 为 `com.Vita0818.Mopelium`。不得把 Mac App Store App Sandbox 限制带回产品设计、依赖选择或默认验证；不得把“无 App Store 约束”误解为可以移除
  PermissionEngine、Lease、PathConfinement、SecretScanner、Seatbelt 或
  Hardened Runtime。
- 持久化：`EventLog`（`~/Library/Application Support/Mopelium/<session>/events.jsonl`）是 session canonical truth；append/batch 在跨进程锁内分配单调 `seq`，settings revision 也在同一事务边界分配，返回值/subscriber 发布实际落盘 bytes 反解的 canonical Envelope；production Cowork runtime 全生命周期持有 writer lease，旧 JSONL 必须继续可解码。`session.json` 是 owner-only、schema v2、可由 EventLog 重建的派生投影，含 `projectedThroughSeq`、settings revision、Cowork settings、agent/workspace/capability 摘要与 migration marker；缺失、损坏、落后或伪造领先时 EventLog 胜出，合法未知 future event 时旧程序不得覆盖投影。`workspace-access.plist` 是 session-owned、schema v1、owner-only binary plist，只保存 canonical path、opaque security-scoped bookmark 与 primary 标志；bookmark bytes 不得进入 JSONL/session.json，App 以 RAII lease 成对持有 scope，恢复时必须先启用 scope 再校验 canonical identity。共享 capability 只有 settings + live roster 都证明零引用才可清理；primary 在 UI/方法/store 默认拒删，只有未成立的创建事务失败回滚可显式删除。旧 Cowork settings/bookmark UserDefaults 仅是一次性迁移输入：必须按具体 session/path 核对来源、迁完全部所需 capability、读回验证并写 durable marker 后才清理，失败保留以便重试。`ArtifactStore` 保存 blobs + `index.json`。全局 `UserDefaults` 仍保存 provider catalog（`mopelium.providerCatalog.v1`）与聊天页当前选择（`mopelium.providerSelection.v1`，另有 `mopelium.baseURL`/`mopelium.model` 兼容镜像）；高级 macOS JSON/JSONC 配置继续按 `MOPELIUM_CONFIG`、`~/.config/mopelium/mopelium.json[c]`、app support `mopelium.json[c]` 与旧 `~/.config/mopelium/config.json` 兜底优先级读取。provider/model options/variants 必须按原始 JSON 保真到 wire adapter，凭据只从 Keychain/env/file/auth/config 懒加载，不得写入事件、投影或项目文档。
- Phase A durable 文件：`submitted-intent-outbox.json` 是 session-owned schema v1 owner-only 暂存，只在 canonical `user_message + queued(attempt 1)` 原子落盘前存在；`SubmissionID` first-write-wins、attempt one-based 单调、retry 复用 exact task 且不重复 user message。`ArtifactStore` 的 root/blobs/index/lock 必须 current-UID、no-follow、owner-only/single-link，索引在稳定锁内 read-merge-atomic-write；unsafe mode/symlink/hardlink fail closed，无法证明 rename durability 时返回 `commitUncertain`。
- production Code/Cowork registry 不暴露 raw `run_shell`；macOS DeveloperID 与 CLI 的 shell-capable Code/Cowork runtime 改为显式提供 runtime-owned `exec_command` / `write_stdin` managed terminal。它是真实持久进程/PTY，但每次启动和后续输入仍必须经过 ToolRegistry、CapabilityLease、PermissionEngine 与 durable tool ticket，并按 exact session/agent/task/attempt/WorkspaceLease/root identity 隔离；默认断网，macOS 走 Seatbelt，取消、task terminal 与 runtime shutdown 必须先 drain 进程。交互输入不得原样进入 EventLog/permission preview，延迟回显也必须清洗；危险命令 guard 必须跨调用跟踪已支持的行输入，无法可靠还原的 cursor/completion/history/escape/keymap 改写 fail closed，partial-write uncertainty 必须终止 session。terminal executor 必须把不可移除的敏感凭据路径清单并入任何新旧 WorkspaceLease，并以大小写无关的 Seatbelt denied rules 执行。read-only worker、reviewer 与禁用 shell 的 host 不得看到这两个工具。不得重新启用 raw `run_shell`，不得退回裸 shell；Linux 仅在 bwrap 可用时运行，否则 fail closed，PTY 当前仍不支持。structured browser/document backend 与 managed terminal 分流，但同样必须有 timeout/cancel 与进程清理。
- 普通 Office/HTML/EPUB 读取不再暴露聚合 `document_read`。五个初读 exact 工具为 `read_docx` / `read_pptx` / `read_xlsx` / `read_html` / `read_epub`，schema 必须继续只有 `path` 与可选 `maxCharacters`；对应五个 `continue_*_read` 工具只能增加 required opaque `cursor`，cursor 必须绑定 exact format 与 host-computed source SHA-256。格式由工具名固定，内容转换、结构遍历、范围 Markdown 序列化和 semantic landmarks 统一来自固定 external Docling `DocumentConverter` / `iterate_items` / `export_to_markdown(from_element:to_element:)` / `HierarchicalChunker` APIs；Mopelium 只实现 hostile-input preflight、identity、窗口/游标、权限/sandbox/envelope，不得恢复 model-authored format/options/backend、手写 OOXML/HTML/EPUB parser/object traversal 或 raw Docling dict。十个 reader tool 的 intent 为 exact `structured_read_only + safeToReplay`：解析失败必须结算为 failed observation 并允许同批其他读取继续，不能升级成整轮终止；该语义不得扩宽到 OCR、写入、网络或任意 exec。fresh lease 仍只发五个 exact format capability，每个 capability 同时暴露其初读和继续工具；legacy `documentRead` 只为旧 session 映射到这十个 concrete tools，不恢复旧聚合工具。PDF 普通正文读取仍走 `read_pdf`；`inspect_pdf` 与它共用 `readPDF` capability，只用 PDFKit 返回 host source SHA-256/byte/page/native-text-OCR status，不返回正文，其 SHA 供 image-only PDF 的显式 `ocr_pdf.expected_source_sha256` 使用；Docling PDF 只保留该显式 OCR 路径。文档 process tree 必须保留独立 2 GiB aggregate RSS ceiling。
- 新会话不得暴露 `document_ocr` / `document_render` / `document_export_pdf` / `document_write` 聚合工具。OCR 只有 `ocr_pdf`，固定对接 Docling `DocumentConverter` 与 Tesseract；页面渲染只有 `pdf_render_page`，每次固定对接 PDFKit `PDFPage.draw` 产出一张 PNG；PDF 导出按输入格式拆为 `docx_export_pdf` / `pptx_export_pdf` / `xlsx_export_pdf` / `html_export_pdf`，分别固定对接 LibreOffice Writer/Impress/Calc PDF filter 与 `WKWebView.createPDF`。写入只暴露 `ExactDocumentToolCatalog` 中的一操作一工具 DOCX/PPTX/XLSX surface；不得恢复 model-authored `format` / `mode` / `operations[]`、HTML/EPUB 写入、PPTX/XLSX chart、XLSX range/style/table/name、写后 preview/recalc/第二层 verifier 或 backend fallback。`compile_latex` 只允许固定 Tectonic，不探测或回退 `latexmk` / `xelatex` / `pdflatex`。这些 model-facing 工具可以共用宿主的 snapshot、CAS、permission、sandbox、timeout、版本 envelope 与原子提交管道，但该管道不得解释或组合业务操作。
- 工作区图片查看只暴露 path-only 的 `view_image`，并与 `read_file` 一同由 `readWorkspace` capability 授权；它只接受现有 PNG/JPEG，经 PathConfinement/WorkspaceLease 后把 exact path 交给 Apple ImageIO + exact-session ArtifactStore，再通过既有 function-output image pipeline 把像素送入下一次模型请求。不得在该工具中加入手写图片 parser、OCR、编辑、缩放、格式转换、远程读取或自动文档渲染；`pdf_render_page` 与 `view_image` 必须保持两个独立调用，后者只能使用前者成功 ToolResult 已确认的 PNG 路径。permission reviewer 仍无任何工具。
- shipping `MopeliumMac` 只能使用 App bundle 内 active-architecture external runtime；CLI/debug 的用户 runtime 只是开发 fallback。发行必须由 `release-spec.json`、`ThirdPartyNotices/DocumentReadingRuntime.md`、`scripts/validate-document-runtime.sh` 与 release script 的入 App 前后复验共同证明 exact version/hash/SBOM/license/architecture/signature；没有真实双架构签名 roots 和 clean-machine 证据时不得声称发行制品完成。
- 安全：`KeychainRef` 是历史类型名，GUI 不访问 OS Keychain；`ConfigSecretResolver` 只在真实 provider 请求中按 env/file/auth JSON/Mopelium-owned OpenCode-compatible config `options.apiKey` 懒加载 secret 并做进程内缓存。macOS auth JSON 优先 `~/.config/mopelium/auth.json`，再读 canonical local-share 与有界 legacy Intatis-owned 路径；不默认读取 OpenCode app 的 auth/config。另保留 `PathConfinement`、`SecretScanner`、Developer ID Hardened Runtime，以及 managed terminal 自有的 workspace-scoped Seatbelt/default-network-deny；这些安全边界与 Mac App Store App Sandbox 无关。

不确定的模块必须标注 `UNKNOWN` 或 `需要后续确认`，不要编造。

## 文档索引

- `SNAPSHOT.md`：当前根基线的来源 commit、复制范围和后续刷新规则。
- `docs/MOPELIUM_PRODUCT_DIRECTION.md`：显示品牌边界、Cowork-only 新功能策略和 Chat/Code 保留规则。
- `docs/PROJECT_MAP.md`：目录、target、入口、关键文件、生成物和脚本地图。
- `docs/MACOS_DISTRIBUTION.md`：macOS Developer ID 直接分发决策、遗留
  App Store target 状态、仍须保留的运行时安全边界和默认验证矩阵。
- `docs/ARCHITECTURE.md`：总体架构、主要链路、数据模型、权限与安全机制。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、风险、工作区改动。
- `docs/TESTING.md`：环境、构建、测试、lint/format 与手动验证方式。
- `docs/DO_NOT_BREAK.md`：工程禁区、数据格式、协议、路径和回归要求。
- `docs/OPEN_SOURCE_REUSE.md`：开源源码/公开 prompt/依赖准入、provenance、Apple-first 集成、NOTICE 与上游升级规则。
- `docs/NEXT_TARGET.md`：临时下一目标记录；目标完成或不再有效后删除。
- `docs/COWORK_PRINCIPLES.md`：Cowork 架构原则（agent 身份/任务契约/能力租约/上下文投影/递归禁止/安全边界/实现顺序/测试期望）。
- `docs/AI_PROVIDER_MODEL_CONFIGURATION.md`：沿用 Mopelium 内部身份的 provider/model/variant 配置合同。
- `docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md`：已被当前快照落地取代的历史迁移审计。

## 完成标准

完成任务前至少做到：

- 说明本轮实际阅读/检查过哪些源码、配置或测试。
- 只修改任务范围内文件。
- 保留用户已有改动。
- 运行与任务相称的检查；文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将本轮已完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 如未运行构建或测试，最终报告必须明确写"未运行构建/测试"。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写无法确认。
2. `PATH_CHECK_RESULT`：`pwd`、Git root、是否匹配预期。
3. `FILES_WRITTEN`：新增/修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、主要模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：各文档内容摘要。
6. `VALIDATION_RESULT`：实际运行命令与结果。
7. `UNCERTAINTIES`：无法确认、需要人工确认的点。
8. `NEXT_RECOMMENDED_ACTION`：下一步建议；不要自动继续改业务源码。
