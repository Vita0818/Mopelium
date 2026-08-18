# MOPELIUM_PRODUCT_DIRECTION

文档状态：当前产品方向与内部身份合同
生效日期：2026-08-17
最近核对：2026-08-18
产品基线：v0.12（build 50）

## 1. 一句话定义

Mopelium 是唯一当前产品身份，也是当前仓库、Swift package、target、module、App、CLI、配置、路径与新协议输出的 canonical namespace。

当前代码仍来自 `SNAPSHOT.md` 固定的 Intatis 来源快照；这条 provenance 不因产品重命名而消失。迁移只原位重命名同一套 runtime，不复制第二套 AgentKernel、EventLog、scheduler、permission、session runtime、MessageBus、Mediator 或工具链。

## 2. 产品面

- 唯一 App 产品：macOS Developer ID/direct-distribution `MopeliumMac`。
- 唯一 App Bundle ID：`com.Vita0818.Mopelium`。
- 用户可见入口：Cowork。
- Chat 与 Code：保留源码、数据兼容、共享 runtime 和测试，但不作为当前 macOS 可见产品入口。
- CLI：`mopelium`，保留 Chat/Code/Cowork headless 工作流。
- iOS：不再提供 App、target、scheme、资源或发行矩阵。
- Mac App Store：不再保留 target、entitlements、编译分支或发行矩阵。

所有新的 Mopelium 产品功能继续只在 Cowork 内建设；不得为了内部改名新建与 Cowork 并列的第四模式。

## 3. Canonical 内部身份

当前新写入和新生成内容使用：

- `MopeliumMac`、`MopeliumCLI`、`mopelium`；
- `MopeliumCore`、`MopeliumProtocol`、`MopeliumProviders`、`MopeliumArtifacts`、
  `MopeliumConversation`、`MopeliumTools`、`MopeliumKnowledge`、`MopeliumSkills`、
  `MopeliumPermission`、`MopeliumMCP`、`MopeliumMCPStdio`、`MopeliumAgentKernel`、
  `MopeliumCowork`、`MopeliumMultimodal` 与 `MopeliumSharedUI`；
- `MOPELIUM_*`、`mopelium.json[c]`、`~/.config/mopelium/`；
- `~/Library/Application Support/Mopelium`；
- `.mopelium/` 与 `.mopelium-rag-*`；
- `mopelium.*`、`mopelium:*`、`urn:mopelium:*` 和 Mopelium registry identity；
- request-owned permission sidecar `__mopelium_authorization_context`。

精确映射、执行状态和兼容边界见 `MOPELIUM_INTERNAL_IDENTITY_MIGRATION.md`。

## 4. 旧身份兼容

旧 Intatis identity 不是当前 canonical namespace，但可出现在以下有界位置：

- `SNAPSHOT.md`、历史报告、旧发布/公证事实和第三方 provenance；
- legacy config/env/UserDefaults decoder 或有界 session migration；
- legacy adapter、registry、EventLog 或 schema decoder/fixture；
- legacy `.intatis` workspace/Knowledge 安全 deny floor；
- 兼容测试中用于证明旧值不会扩大权限或覆盖新值的输入。

旧顶层 `~/Library/Application Support/Intatis` 与旧 macOS bundle UserDefaults domain
不再是兼容输入：App/CLI 只使用 Mopelium canonical root/domain，完全忽略旧根/domain；
不读取、不迁移、不合并，也不因其存在而阻止启动。旧目录由用户自行保留或处置，Mopelium
不会删除它。

兼容原则是“新名优先、旧名只读、新写只用 Mopelium”：

1. 新 canonical 值存在但非法时 fail closed，不得回退旧值。
2. App/CLI 不得探测或迁移旧顶层 Application Support 根；双根存在是合法外部状态，旧根必须被忽略。
3. macOS App 启动不得从旧 bundle domain 导入 UserDefaults；仍保留的 session 内 legacy decoder/migration 必须有独立明确合同。
4. 历史 EventLog 和已签名/已提交 artifact 不做字符串原地重写。
5. 新旧状态不得双写或静默合并。

## 5. Cowork 与安全边界

内部 namespace 变化不得改变：

- Goal、Session-scoped WorkTask、ContinuationRun 与 AgentInvocation 的独立事实边界；
- `@main`、ordinary agents、Permission Reviewer 与 Goal Verifier 的身份和推理绑定边界；
- AgentScheduler、TaskGraph、mailbox、MessageBus 与 Mediator；
- CapabilityLease、WorkspaceLease、PathConfinement、SecretScanner；
- DeterministicPolicyGate → ModelPermissionReviewer/control plane → PermissionEngine；
- EventLog append-only、durable tool prepare/settle、replay、recovery 和 projection；
- managed-terminal Seatbelt/default-network-deny、Hardened Runtime 与 Developer ID 分发。

不得让 `AgentLoop` 同步递归调用另一个 `AgentLoop`，不得让 worker 因重命名获得 coordinator 能力，也不得让 legacy decoder 成为权限 fallback。

## 6. 配置与凭据

- canonical 配置：`MOPELIUM_CONFIG`、`mopelium.json[c]`、Mopelium provider catalog；
- canonical CLI override：`MOPELIUM_MODEL`、`MOPELIUM_BASE_URL`、`MOPELIUM_API_KEY`、`MOPELIUM_REASONING`；
- legacy `INTATIS_*` 和旧路径只在对应 canonical 值缺失时读取；
- canonical 值存在但损坏时不回退；
- secret 继续只从受控 reference 懒加载，不进入 EventLog、UserDefaults、诊断包、文档或工具输出。

精确配置合同见 `AI_PROVIDER_MODEL_CONFIGURATION.md`。

## 7. 文档权威顺序

1. 当前源码、`Package.swift`、`project.yml`、测试和脚本决定实现事实；
2. 本文件决定产品面与 canonical/legacy 身份边界；
3. `MOPELIUM_INTERNAL_IDENTITY_MIGRATION.md` 决定本次迁移映射和验收；
4. `CURRENT_STATE.md`、`ARCHITECTURE.md`、`PROJECT_MAP.md`、`DO_NOT_BREAK.md` 与
   `COWORK_PRINCIPLES.md` 解释当前实现约束；
5. `SNAPSHOT.md`、`INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md` 和 dated reports 只保留历史/provenance。

## 8. 当前非目标

- 不删除 Chat/Code runtime、数据兼容或测试；
- 不新建 Mopelium 平行后端；
- 不改变 EventLog 既有 JSONL bytes 或任意第三方许可证原文；
- 不以重命名为由削弱权限、workspace、secret、sandbox、签名或恢复边界；
- 不自动执行真实 provider 请求、签名、公证、上传、安装或发布。
