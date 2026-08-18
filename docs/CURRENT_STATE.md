# CURRENT_STATE

文档状态：当前源码摘要
最近核对：2026-08-18
产品基线：v0.12（build 50）

## 当前产品与内部身份

- 当前仓库、Swift package、Xcode project、target、module、App、CLI、配置、路径与新协议输出的 canonical 产品身份是 Mopelium。
- 源码 provenance 仍是 `SNAPSHOT.md` 固定的 Intatis commit；历史来源、旧 EventLog bytes、dated reports 和第三方许可证不做品牌重写。
- 唯一 App target：`MopeliumMac`。
- 唯一 App Bundle ID：`com.Vita0818.Mopelium`。
- macOS 分发：Developer ID、notarization、direct download；不做 Mac App Store。
- 当前没有 iOS App target、scheme、资源树或发行矩阵。
- Swift-native CLI target/product：`MopeliumCLI` / `mopelium`。
- 用户可见 App 入口只有 Cowork；Chat 与 Code 源码、数据兼容、共享 runtime 和测试仍保留。

## 当前视觉主题

- macOS 当前使用暖色 / 淡香槟配色：暗色为轻暖深灰渐变，亮色为暖白奶油渐变；上一轮过灰的文字、canvas 与非玻璃 affordance 已恢复适度暖度，但不使用棕黄或高饱和金色。
- `MopeliumTheme` 是固定品牌 token、明暗渐变、文字和描边的单一 App 来源。淡香槟只进入 canvas、文字、选中与结构描边，不进入 Glass tint。
- 所有非破坏性 Glass button 在当前系统统一为无 tint 的 `.glass`；不再使用 `.glassProminent`。用户气泡、composer、选择控件和 Cowork rail 直接使用无 tint 的 SwiftUI 原生 `Glass.regular` / `Glass.clear` 与 `glassEffect`。Stop 继续是同形态的系统 destructive red 例外。
- 根视图通过 SwiftUI 官方 `.window` container background 让同一暖色 canvas 覆盖 window titlebar，并隐藏 `.windowToolbar` backing；右侧不再出现系统白条，sidebar 仍保留独立系统材质。
- App 图标由根 `Mopelium.icon` 的单层 `Assets/Mopelium.png` 提供：当前使用用户提供的 1254×1254 RGB、无 alpha PNG 原始字节，不再做调色或其他像素处理；以 scale `0.95`、零位移进入 Apple Icon Composer，不叠加旧指针图、额外阴影或 translucency。当前 PNG SHA-256 为 `4199874c81c488c23579d4b8e431941fceb488690b05ce3b53ab778d62542ca1`。
- 当前图标的 unsigned Debug 与 universal Release build、`Mopelium.icns`、`Assets.car` 结构/多尺寸 rendition 和编译图标视觉读回均已通过。本次替换未重启 LaunchServices、IconServices、Dock 或 Finder，因此已安装 App 的系统缓存显示仍为 `UNKNOWN`，不以缓存状态反向修改源图。
- 当前精确规范见 `CURRENT_UI_COLOR_SYSTEM.md`；`UI_COLOR_SYSTEM.md` 保存重新启用的 palette 来源和旧实现 provenance。
- 原生 Glass 接线阶段完整 SharedUI 153 tests / 0 failures；本轮统一无色 Glass 与 window-toolbar 修复后的 `ThreadLayoutTests` 为 23 tests / 0 failures，SharedUI focused build、XcodeGen 与 `MopeliumMac` unsigned Debug build 通过。Light 模式 Settings 和用户对应 Cowork 会话已用本机界面控制确认 titlebar/detail 暖色连续、白条消失；Dark、Reduce Transparency、Increase Contrast、VoiceOver 与 active/inactive window 仍为 `UNKNOWN`。默认真实双根环境完整 SwiftPM command 在排除 `TESTING.md` 已记录的两项 provider 基线冲突后仍有此前 exit-0 证据。

## 当前构建图

根 `Package.swift` 定义：

- 15 个公共 library products：`MopeliumCore`、`MopeliumProtocol`、`MopeliumProviders`、
  `MopeliumArtifacts`、`MopeliumConversation`、`MopeliumTools`、`MopeliumKnowledge`、
  `MopeliumSkills`、`MopeliumPermission`、`MopeliumMCP`、`MopeliumMCPStdio`、
  `MopeliumAgentKernel`、`MopeliumCowork`、`MopeliumMultimodal`、`MopeliumSharedUI`；
- 3 个内部 C/guard targets：`MopeliumPTYLauncher`、`MopeliumCurlTransport`、
  `MopeliumMCPStdioGuard`；
- `MopeliumCLI`、开发期 `MopeliumMCPConformanceClient`；
- 15 个对应的 `Mopelium*Tests` targets。

`project.yml` 只定义 `MopeliumMac` target/scheme，链接完整 macOS product graph，使用
`Apps/MopeliumMac/MopeliumMac.DeveloperID.entitlements`、Hardened Runtime 与最小 audio-input entitlement。

## 运行时主链

- Chat：`ChatViewModel → GoalInputParser → ChatLoop → EventLog → ConversationProjection`；
- Code：`CodeViewModel → AgentRuntime.code → AgentLoop → ToolRegistry/PermissionEngine → EventLog → CodeProjection`；
- Cowork：`CoworkViewModel → SubmittedIntentStore → Orchestrator → FIFO scheduler → AgentRuntime.cowork → AgentLoop → durable tool execution → EventLog`；
- Agent 通信：`MessageBus → Mediator → mailbox/event flow`；
- 自动权限：acting-model same-call sidecar → deterministic gate → independent permission-review control plane → durable settlement → exact authorization delivery。

原位改名没有复制 AgentKernel、EventLog、scheduler、permission、session runtime、MessageBus、Mediator 或工具执行器。

## 持久化与身份迁移

Canonical state：

- `~/Library/Application Support/Mopelium`；
- `~/.config/mopelium/mopelium.json[c]`；
- `~/.local/share/mopelium/`；
- `MOPELIUM_*`；
- `mopelium.*` UserDefaults；
- `.mopelium/` workspace state；
- `.mopelium-rag-*` Knowledge publication；
- `mopelium.standard.v8` / `mopelium.cowork.v8`；
- `__mopelium_authorization_context`；
- `mopelium:siliconflow-v1` / `mopelium:cohere-v2` / `mopelium:legacy-openai-wire`。

有界 legacy compatibility：

- App/CLI 只解析 `~/Library/Application Support/Mopelium`，不会探测、读取、迁移、合并或删除旧 `Intatis` 根；双根存在不影响启动；
- macOS App 不再从旧 bundle domain 导入 UserDefaults；当前 Mopelium domain 只消费 canonical key，session 内另有明确合同的 legacy settings/bookmark migration 不由 App 启动隐式触发；
- config/env/auth 优先 Mopelium；canonical 候选存在但非法时不回退；只有 canonical 缺失才读 `INTATIS_*`、`~/.config/intatis` 或旧文件名；新写只落 Mopelium；
- 旧 adapter raw values 解码时规范化到 Mopelium，重新编码只写 Mopelium；unknown adapter 保持 byte-exact 并在不支持时 fail closed；
- legacy `.intatis` config/Knowledge paths 继续进入 SecretScanner、WorkspaceLease 和 terminal deny floor；已有 `.intatis/git-worktrees` 可安全识别，新建 worktree 只用 `.mopelium`；
- 历史 EventLog/registry strings继续按 additive protocol 解码，但旧 authorization 不因 namespace alias 获得新执行权。

browser profile、Knowledge publication 与 linked Git worktree 不能裸移动；只有对应 owner/lock/drain/Git-aware 边界证明安全后才可做更深迁移。

## 持久化与安全不变量

- `events.jsonl` 是 session canonical truth；append/batch 在跨进程锁内分配单调 seq；
- `session.json` 是可重建 projection，EventLog 永远优先；
- bookmark、artifact、provider catalog、Knowledge access 和 browser profile 各有独立 owner/schema；
- Code/Cowork 工具继续经过 ToolRegistry、CapabilityLease、WorkspaceLease、PathConfinement、
  DeterministicPolicyGate、permission reviewer/control plane、PermissionEngine 和 durable execution ticket；
- production registry 不暴露 raw `run_shell`；managed terminal 使用 runtime-owned
  `exec_command` / `write_stdin`、workspace-scoped Seatbelt、默认断网和 bounded drain；
- SecretScanner/Mediator/credential resolver、Hardened Runtime 与签名边界未弱化；
- `PlatformProfile.current` 仍默认最受限信封；shipping composition root 显式使用 `.macDeveloperID`。

## 文档、媒体、浏览器与 Knowledge

- 文档读取继续使用 exact `read_*` / `continue_*_read`、`inspect_pdf` / `read_pdf`、显式 OCR、单页 render、fixed export 与一操作一工具 write surface；
- shipping document runtime 仍必须从 App bundle 的 active-architecture root 解析，CLI/debug 用户 runtime 只是开发 fallback；
- `view_image` 仍是 path-only PNG/JPEG workspace tool，复用 ImageIO + exact-session ArtifactStore；
- browser state 新写 `.mopelium/browser`，仍经专用 broker、WorkspaceLease、权限和 process cleanup；
- Knowledge 新写 `.mopelium-rag-*`，继续要求 configured embedding/reranker exact route、immutable snapshot、grounding evidence 与 managed-store anti-bypass。

## 发行状态

仓库已具备 universal build、Developer ID signing/notarization/recovery、document-runtime validator 与 ZIP/DMG packaging 脚本，当前脚本身份已改为 Mopelium，并校验 Bundle ID `com.Vita0818.Mopelium`。

尚未完成：

- 经同一 Developer ID identity bottom-up 签名的 arm64/x86_64 external document runtime roots；
- 含这些 roots 的 Mopelium notarized App/DMG；
- staple、Gatekeeper、clean-machine 安装与文档全链验收。

因此当前不得声称正式 release 完成。

## 本次迁移验证状态

截至本文本次写入：

- `swift package dump-package` 已确认 Mopelium package、15 libraries、3 internal targets、CLI、15 tests 与 macOS-only platform graph；
- `swift build --disable-automatic-resolution` 已通过四次，只有仓库既有 warning；
- identity/config/adapter/deny-floor/sidecar/registry/target-inventory/Cowork focused command共执行 60 tests、0 failures；旧 direct migration primitive 的历史测试不再构成 shipping startup 验收；
- 原始完整 `swift test --disable-automatic-resolution` 执行到终点但退出 1，只有两个已独立复现且与 namespace 无关的 retry-boundary 冲突：
  `testOpenAIStreamingDoesNotRetryAfterResponseBytes` 与
  `testOfficialProviderRetryBoundaryStaysInsideOneLogicalGeneration`；
- 显式 `--skip` 上述两个已单列冲突后，完整 SwiftPM command 退出 0；真实 provider/browser/Git/document-runtime 等 opt-in tests 按设计 skipped；
- `xcodegen generate`、版本一致性门、active identity 门通过；Xcode project 只有一个 App target `MopeliumMac`；
- `MopeliumMac` unsigned Debug 与 universal Release 均构建通过；Release bundle 为 `0.12 (50)`、
  `com.Vita0818.Mopelium`、display name Mopelium、executable `MopeliumMac`、`x86_64 arm64`；
- release/validator/version/identity/Linux/scheme shell syntax、release-spec plist parse、EPUBCheck wrapper hash一致性均通过；
- `mopelium-skill-creator` quick validation 与 Python compile 通过；rbook helper fmt、7 unit + 2 integration tests 通过；
- 未运行真实 provider、签名、公证、staple、Gatekeeper、安装、上传或发布。

## 当前已知缺口

1. 旧 browser profile、Knowledge publication 与 linked Git worktree 的自动迁移需要各自独立安全设计；当前新写已切换，旧路径仍受保护或可识别，但不做危险裸移动。
2. 真实 provider/key、MCP/OAuth、浏览器长时 profile、VoiceOver、最低 macOS、Intel 与 Linux 真机仍有环境空白。
3. 双架构 document runtime、签名、公证、staple、Gatekeeper 和 clean-machine release gate 未完成。
4. 历史设计/报告可继续出现 Intatis 和已删除 target；它们不是当前构建事实，必须通过当前文档索引识别。

## 文档治理

当前事实以 `MOPELIUM_PRODUCT_DIRECTION.md`、`MOPELIUM_INTERNAL_IDENTITY_MIGRATION.md`、
本文件、`PROJECT_MAP.md`、`ARCHITECTURE.md`、`DO_NOT_BREAK.md` 和源码为准。
历史验证数字、旧 target/path 和事故记录留在 Git 历史、`SNAPSHOT.md` 与 dated reports，不再回填成当前事实。
