# MOPELIUM_PRODUCT_DIRECTION

文档状态：当前产品方向与品牌边界
生效日期：2026-08-06
产品代码基线：Intatis v0.36（build 36）

## 1. 一句话定义

Mopelium 是构建在现有 Intatis Cowork 运行时之上的用户可见产品品牌与领域化体验。

它不是新的后端内核、不是 Intatis 的全仓重命名，也不是与 Cowork 并列的第四种运行模式。
后续产品功能统一在 Cowork 内建设；Chat 与 Code 保留现有实现，未来只从面向用户的产品入口
隐藏，不删除、不拆除，也不另行迁移。

## 2. 当前事实与目标状态

必须区分当前源码事实和仍待后续实施的产品方向：

| 范围 | 当前事实 | 已确认方向 |
|---|---|---|
| 代码基线 | 仓库根目录直接采用 Intatis 快照 | 继续直接修改当前根目录，不维护第二套源码 |
| 显示品牌 | macOS、iOS 与 CLI 的用户可见品牌文字显示 Mopelium | 继续保持 presentation-only，不扩散为内部改名 |
| 内部标识 | target、模块、类型、Bundle ID、命令、配置键和存储路径使用 Intatis | 默认全部保留，不做后端或源码级品牌替换 |
| macOS 模式 | Chat / Code / Cowork 当前均存在并可见 | Mopelium 只以 Cowork 为产品面；Chat/Code 后续隐藏但保留 |
| 新功能 | 当前能力分布在三个模式 | 新增 Mopelium 产品功能只接入 Cowork |
| iOS | 当前是 Intatis Chat 结构性子集，显示品牌文字为 Mopelium | 不扩展、删除或重构 iOS |
| CLI | 用户可见 banner/自检文案为 Mopelium，命令与内部协议使用 `intatis` | 保持内部工具身份 |

显示品牌文字已按本文件边界落地；Chat/Code 隐藏及其他产品变化尚未实施。源码、构建配置和
测试仍是“当前实现”的事实源。

## 3. 显示品牌边界

### 3.1 用户可见层

- App 显示名称、窗口与导航中的品牌文字；
- 面向用户的空态、设置说明、帮助、发行页面和产品文案；
- Logo、图标及其他明确的品牌视觉资产；
- 面向用户的 Cowork 信息架构和领域化工作流名称。

本次只落实显示名称与用户可见文字。Logo、图标及其他视觉资产仍须由用户单独授权后修改。

### 3.2 默认保持 Intatis 的内部层

- `IntatisMac`、`IntatisiOS`、`IntatisCLI` 等 target 与 executable identity；
- `IntatisCore`、`IntatisProtocol`、`IntatisCowork` 等 Swift 模块；
- Swift 类型名、源码目录名和测试 target 名；
- Bundle ID、entitlements、scheme、XcodeGen/SwiftPM product 名；
- `INTATIS_*` 环境变量、`intatis.json[c]`、`~/.config/intatis/`；
- Application Support 目录、UserDefaults key、EventLog payload/schema、SessionID 和 durable 文件名；
- `intatis` CLI 命令、内部诊断标识和协议兼容名称。

不得为了显示品牌一致而对这些内部标识做机械替换。确需改变任一内部标识时，必须作为独立
迁移任务评估持久化兼容、配置发现、签名、升级路径、CLI 和测试影响。

真实第三方归属、`NOTICE.md` 和历史 provenance 也不得因品牌变化而改写。

## 4. Cowork 是唯一新增产品功能承载面

所有新的 Mopelium 功能都应视为对 Cowork 的领域化修饰或扩展，而不是新建模式或平行内核。

新增能力必须优先复用：

- `IntatisCowork` 的 Goal、WorkTask、ContinuationRun 和 AgentInvocation；
- `@main`、ordinary agents、Permission Reviewer 与 Goal Verifier 的既有身份边界；
- AgentScheduler、TaskGraph、mailbox、MessageBus 与 Mediator；
- AgentKernel、ToolRegistry、Skills、MCP、Artifacts 和 provider profile；
- CapabilityLease、WorkspaceLease、PermissionEngine、PathConfinement 与 SecretScanner；
- EventLog、durable tool prepare/settle、replay、recovery 和 projection。

研究、资料、来源、阅读、证据核验、报告等领域能力可以成为 Cowork 内的工具、Skill、任务语义、
artifact、projection 或界面，但不得建立第二套 `MopeliumAgentKernel`、调度器、消息总线、权限链、
EventLog 或 session runtime。

## 5. Chat 与 Code 的保留规则

Chat 和 Code 当前仍是代码基线的一部分。未来隐藏时：

- 只改变面向用户的导航、入口或默认展示；
- 不删除 App 页面、Swift target、package、runtime、EventLog 兼容或测试；
- 不把历史 Chat/Code session 数据迁成 Cowork；
- 不让隐藏动作改变共享 runtime 的 shutdown、recovery 或 session ownership；
- 不把 Chat/Code 的功能复制一份到新的 Mopelium 模式；Cowork 通过既有共享模块使用所需能力；
- 在用户明确发出隐藏实现任务前，保持当前可见性与行为不变。

共享底层修复仍可同时改善 Chat/Code，但 Mopelium 产品需求不再为它们建立独立功能面。

## 6. 配置与凭据解释

显示品牌决定不改变 provider/model/variant 的内部配置身份。当前实现继续以 `INTATIS_CONFIG`、
`intatis.json[c]`、Intatis provider catalog 和 exact `AgentInferenceBinding` 为准。

项目对 AI 维护者的安全写入规则见 `AI_PROVIDER_MODEL_CONFIGURATION.md`。该文档可以规定比
runtime 兼容面更严格的 AI 操作纪律，但不得把 `MOPELIUM_*`、Mopelium 配置目录或全仓类型重命名
描述为已实现或默认目标。

## 7. 文档权威顺序

1. 当前源码、`Package.swift`、`project.yml`、测试和脚本决定当前实现事实；
2. 本文件决定 Mopelium 的产品方向、品牌边界和功能承载面；
3. `CURRENT_STATE.md`、`ARCHITECTURE.md`、`PROJECT_MAP.md` 和 `COWORK_PRINCIPLES.md` 解释当前状态与实现约束；
4. `INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md` 等旧报告只保留历史背景，不再提供执行计划。

若历史文档要求新建 Mopelium 后端模块、重命名 Intatis 内部标识、选择性迁移 Cowork 内核或删除
Code/Git 产品代码，该结论已经被本文件取代。

## 8. 当前非目标

- 不为显示品牌修改业务逻辑、运行时或数据；本次只修改 presentation 字符串与显示名称元数据；
- 不执行 `Intatis` → `Mopelium` 的全仓字符串、类型或模块替换；
- 不新建与 Cowork 并列的 Research、Sources、Tasks 或 Mopelium runtime；
- 不删除 Chat、Code、iOS 或 CLI；
- 不因未来隐藏 Chat/Code 而提前削弱它们的构建和回归；
- 不自动把快照原有的 Intatis v0.36 公证任务当作 Mopelium 当前发布目标；
- 不在用户指定下一实现任务前继续修改产品代码。
