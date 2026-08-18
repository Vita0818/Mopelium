# PROJECT_MAP

文档状态：当前仓库地图
最近核对：2026-08-18
产品基线：v0.12（build 50）

本文描述内部身份迁移后的当前构建图。事实源是 `Package.swift`、`project.yml`、源码、测试与脚本；`SNAPSHOT.md` 单独保留 Intatis 来源树的历史身份。

## 目录结构

```text
Mopelium/
├── .agents/skills/mopelium-skill-creator/
├── Apps/
│   ├── MopeliumMac/             唯一 App target
│   ├── SharedResources/         macOS 本地化 String Catalog
│   └── mopelium-cli/            Swift-native CLI 与测试
├── Mopelium.icon/               Apple Icon Composer 源；单层 Assets/Mopelium.png
├── Packages/
│   ├── MopeliumCore/
│   ├── MopeliumProtocol/
│   ├── MopeliumProviders/
│   ├── MopeliumArtifacts/
│   ├── MopeliumConversation/
│   ├── MopeliumPTYLauncher/
│   ├── MopeliumTools/
│   ├── MopeliumKnowledge/
│   ├── MopeliumSkills/
│   ├── MopeliumPermission/
│   ├── MopeliumCurlTransport/
│   ├── MopeliumMCP/
│   ├── MopeliumMCPStdio/
│   ├── MopeliumMCPConformanceClient/
│   ├── MopeliumAgentKernel/
│   ├── MopeliumCowork/
│   ├── MopeliumMultimodal/
│   └── MopeliumSharedUI/
├── Vendor/                      固定并记录 provenance 的派生包
├── ThirdPartyNotices/           当前分发声明与完整许可证入口
├── ThirdPartyStandards/         byte-exact 第三方标准
├── Tests/                       MCP conformance / BM25 parity
├── docs/                        当前规范与显式历史文档
├── scripts/                     构建、验证、诊断、发行
├── Package.swift                SwiftPM 构建图
├── project.yml                 XcodeGen 唯一 App 工程图
├── NOTICE.md
└── SNAPSHOT.md                 Intatis 来源 commit/provenance
```

生成或本地状态：

- `.build/`、`.swiftpm/`：SwiftPM；
- `Mopelium.xcodeproj/`：XcodeGen 生成物；
- `.mopelium/`：当前本地 workspace/release 状态；
- `.intatis/` 与 `Intatis.xcodeproj/`：只为迁移期忽略的 predecessor 状态，不是当前构建输入；
- `dist/`：发行输出，只有正式脚本完成所有门槛后才可使用。

## SwiftPM products 与 targets

### 15 个公共 library products

| Target | 主要职责 |
|---|---|
| `MopeliumCore` | ID、错误、PlatformProfile、路径约束、session 历史、owner-only durable file、Application Support identity migration |
| `MopeliumProtocol` | Event/Envelope、Goal/WorkTask/Run、lease、permission、tool execution、model history、MCP 与 multimodal wire vocabulary |
| `MopeliumProviders` | provider catalog、exact route、OpenAI-compatible/Responses/OpenRouter wire、streaming、image/transcription/Knowledge adapters |
| `MopeliumArtifacts` | owner-only blob/index store 与安全图片解析 |
| `MopeliumConversation` | append-only EventLog、ChatLoop、projection、session.json、submitted-intent outbox 与恢复 |
| `MopeliumTools` | file/patch/Git/managed terminal/browser/document/media/Knowledge host seams 与 ToolRegistry |
| `MopeliumKnowledge` | OKF profile、validator、build/publish、snapshot、embedding/BM25/rerank/search/grounding |
| `MopeliumSkills` | Skill discovery/snapshot/catalog/resource tools；不授予权限 |
| `MopeliumPermission` | DeterministicPolicyGate、ModelPermissionReviewer、PermissionEngine、SecretScanner |
| `MopeliumMCP` | 外部 MCP client-only core、HTTP/OAuth/catalog/callback/task/output security |
| `MopeliumMCPStdio` | stdio process owner、Seatbelt/bwrap/guard、network gateway、drain |
| `MopeliumAgentKernel` | 共享 headless AgentRuntime/AgentLoop、context/history/compaction、permission responder |
| `MopeliumCowork` | Orchestrator、scheduler、MessageBus/Mediator、WorkTask/Goal、permission reviewer、goal verifier |
| `MopeliumMultimodal` | image/video/transcription → artifact |
| `MopeliumSharedUI` | macOS SwiftUI conversation、composer、Cowork/thread、renderer 与共享 presentation |

### 3 个内部 C/guard targets

- `MopeliumPTYLauncher`：macOS controlling PTY；
- `MopeliumCurlTransport`：macOS/Linux libcurl socket-binding boundary；
- `MopeliumMCPStdioGuard`：Linux seccomp/ptrace guard，Apple 平台为空实现。

### Executables

| Target/product | 用途 |
|---|---|
| `MopeliumCLI` / `mopelium` | Chat/Code/Cowork REPL、managed execution、Skills、Knowledge、MCP |
| `MopeliumMCPConformanceClient` | 开发期 official/extended MCP client conformance driver；不发行 |

### Test targets

15 个 test target 与公共模块对应：

```text
MopeliumCoreTests
MopeliumProtocolTests
MopeliumProvidersTests
MopeliumArtifactsTests
MopeliumConversationTests
MopeliumToolsTests
MopeliumKnowledgeTests
MopeliumSkillsTests
MopeliumPermissionTests
MopeliumMCPTests
MopeliumCLITests
MopeliumAgentKernelTests
MopeliumCoworkTests
MopeliumMultimodalTests
MopeliumSharedUITests
```

## Xcode App target

| Target | 平台 | Bundle ID | 分发 |
|---|---|---|---|
| `MopeliumMac` | macOS 26+ | `com.Vita0818.Mopelium` | Developer ID、notarization、direct download |

不存在 iOS App target、Mac App Store target、App Store entitlements 或对应 scheme。`MopeliumMac` 使用 `Apps/MopeliumMac/MopeliumMac.DeveloperID.entitlements`，启用 Hardened Runtime 和最小 audio-input entitlement，不启用 App Sandbox。

## 产品入口

- macOS：`Apps/MopeliumMac/Sources/MopeliumMacApp.swift`；
- CLI：`Apps/mopelium-cli/Sources/MopeliumCLI.swift`；
- 当前用户可见 App 根：`MopeliumMacRootView`，只展示 Cowork；
- Chat/Code ViewModel 与 runtime 仍在同一 App 源码和共享 packages 中保留兼容。

## UI 主题入口

- `Apps/MopeliumMac/Sources/MopeliumDesign.swift`：暖色 / 淡香槟固定 token、Light/Dark 页面渐变、macOS thread style 与 Material / Glass 结构描边；
- `Packages/MopeliumSharedUI/Sources/ThreadSurfaces.swift`：无 tint 的系统原生 `Glass.regular` / `Glass.clear`、统一 `.glass` button style 与暖色结构描边环境输入；
- `Apps/MopeliumMac/Sources/MopeliumMacRootView.swift`：不注入 Glass/button 品牌 tint 的 system sidebar、detail canvas、`.window` container background 与透明 window-toolbar backing；
- `Mopelium.icon/icon.json` + `Mopelium.icon/Assets/Mopelium.png`：用户提供的 1254×1254 RGB、无 alpha 文档 App 图标原始字节，不做调色或其他像素处理，以单层、scale `0.95`、零位移交给 Apple Icon Composer；
- `docs/CURRENT_UI_COLOR_SYSTEM.md`：当前组件映射和验收；`docs/UI_COLOR_SYSTEM.md`：重新启用的 palette 来源及旧实现 provenance。

## 主要链路

- Chat：`ChatViewModel → GoalInputParser → ChatLoop → EventLog → ConversationProjection`；
- Code：`CodeViewModel → AgentRuntime.code → AgentLoop → ToolRegistry/PermissionEngine → EventLog → CodeProjection`；
- Cowork：`CoworkViewModel → SubmittedIntentStore → Orchestrator → FIFO scheduler → AgentRuntime.cowork → AgentLoop → durable tool execution → EventLog`；
- Agent 通信：`MessageBus → Mediator → mailbox/event flow`；
- 自动权限：acting-model same-call sidecar → deterministic gate → `PermissionReviewControlPlane` → durable settlement → exact authorization delivery；
- 持久化：`Application Support/Mopelium/<session>/events.jsonl` 为 canonical truth，`session.json` 可重建，bookmark/artifact/catalog 各自独立。

## Canonical identity 与 legacy seam

- canonical config：`MOPELIUM_CONFIG`、`~/.config/mopelium/mopelium.json[c]`；
- canonical CLI：`mopelium` 与 `MOPELIUM_*`；
- canonical workspace：`.mopelium/`、`.mopelium-rag-*`；
- canonical registry：`mopelium.standard.v8` / `mopelium.cowork.v8`；
- canonical sidecar：`__mopelium_authorization_context`。

旧顶层 Intatis Application Support 和 macOS bundle domain 被 App/CLI 完全忽略；它们不再进入生产 migrator。config/env、session 内 legacy settings、adapter ID、registry/event raw values 和 `.intatis*` 只由各自显式 decoder/deny floor 处理。新值存在但非法时不回退，历史 JSONL 不重写。

## 关键脚本

- `scripts/check-version-consistency.sh`：`project.yml`、macOS reference plist、当前文档和生成工程版本；
- `scripts/hide-xcode-package-schemes.sh`：只展示 `MopeliumMac` 与 CLI scheme；
- `scripts/package-macos-release.sh`：唯一正式 macOS ZIP/DMG 入口；
- `scripts/validate-document-runtime.sh`：双架构 document runtime 静态/执行门；
- `scripts/validate-linux-cli.sh`：Linux static CLI gate；
- `scripts/RendererValidationWatchdog.swift`：bundle/executable/renderer containment 验证。

## 历史与 provenance

- `SNAPSHOT.md` 中的 Intatis 仓库、commit、旧 target/path 是不可改写的来源事实；
- `docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md` 和 dated reports 不是当前构建地图；
- `NOTICE.md` 与 `ThirdPartyNotices/` 使用当前 Mopelium 路径描述分发闭包，同时保留 upstream 版权、许可证和来源 commit。

## 不确定项

- 双架构签名 document runtime roots、notarized App/DMG 和 clean-machine acceptance 尚未完成；
- 真实 provider、OAuth、长时 browser/profile、VoiceOver 与最低系统真实矩阵仍需单独授权和验证；
- 旧 browser profile、Knowledge publication 和 managed Git worktree 的自动迁移只可在各自 owner/lock/drain 边界证明安全后继续，不能裸移动。
