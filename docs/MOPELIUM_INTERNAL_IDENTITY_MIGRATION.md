# MOPELIUM_INTERNAL_IDENTITY_MIGRATION

文档状态：执行清单与迁移合同
生效日期：2026-08-17
产品基线：v0.10（build 49）

## 1. 已确认决策

- Mopelium 从“仅用户可见品牌”推进为仓库、构建、运行时、配置、路径和新协议身份的 canonical 产品名称。
- 唯一 App 产品是 macOS Developer ID/direct-distribution App。
- macOS Bundle ID 固定为 `com.Vita0818.Mopelium`。
- 不再提供 iOS App：删除 iOS App 源码目录、XcodeGen target/scheme、参考 plist、资源与产品验证门。
- 删除遗留 Mac App Store target、App Store entitlements 和只为该 target 存在的编译分支。
- Chat、Code、Cowork 的既有源码、数据兼容和测试继续保留；用户可见产品入口仍只有 Cowork。
- AgentKernel、EventLog、scheduler、permission、session runtime、MessageBus、Mediator 与工具链只做原位改名，绝不复制出平行 Mopelium 后端。
- 三层权限门、WorkspaceLease、CapabilityLease、PathConfinement、SecretScanner、Mediator、managed-terminal Seatbelt/default-network-deny、Hardened Runtime 和 durable tool execution 不得因迁移而弱化。

## 2. 兼容策略

采用“一次迁移期双读、只写新名”：

1. 新版本只创建、生成和写入 Mopelium canonical identity。
2. 新 canonical 配置、状态或路径不存在时，才允许读取受控的旧 Intatis identity。
3. 新 canonical 输入一旦存在但损坏、非法或不可证明，必须 fail closed，不得回退旧值掩盖错误。
4. 旧数据迁移成功后必须写入并读回 durable migration marker；不得同时向新旧两棵状态树双写。
5. `events.jsonl`、历史 protocol payload、旧配置和既有签名/公证记录不得做字符串级原地重写。
6. 旧 identity 只允许出现在显式命名的 legacy decoder/migrator、兼容 fixture、历史快照、dated report 和 provenance/许可证记录中。
7. 过渡兼容稳定并经过真实升级验收后，再由单独任务删除 legacy reader/alias。

## 3. Canonical 工程映射

### 3.1 Project / App / executable

| 旧 identity | 新 identity |
|---|---|
| Swift package / Xcode project `Intatis` | `Mopelium` |
| `Intatis.xcodeproj` | `Mopelium.xcodeproj` |
| `IntatisMac` | `MopeliumMac` |
| `Apps/IntatisMac` | `Apps/MopeliumMac` |
| `IntatisMacApp` | `MopeliumMacApp` |
| `IntatisCLI` | `MopeliumCLI` |
| `Apps/intatis-cli` | `Apps/mopelium-cli` |
| executable / command `intatis` | `mopelium` |
| `IntatisMCPConformanceClient` | `MopeliumMCPConformanceClient` |
| `Intatis.icon` | `Mopelium.icon` |
| `IntatisMac.DeveloperID.entitlements` | `MopeliumMac.DeveloperID.entitlements` |
| `com.Vita0818.IntatisMac` | `com.Vita0818.Mopelium` |

删除而非重命名：

- `IntatisMacAppStore` target/scheme；
- `IntatisMac.AppStore.entitlements`；
- `INTATIS_MAC_APP_STORE` 条件和仅该条件使用的 dead branch；
- `IntatisiOS` target/scheme 与 `Apps/IntatisiOS` 整棵 App 源码/资源；
- iOS 参考 `Info.plist`、iOS 产品构建/发行检查和 iOS-only App 接线测试。

### 3.2 SwiftPM modules

所有 project-owned target、product、test target、目录、import 和模块前缀按同一规则原位迁移：

| 旧 target | 新 target |
|---|---|
| `IntatisCore` | `MopeliumCore` |
| `IntatisProtocol` | `MopeliumProtocol` |
| `IntatisProviders` | `MopeliumProviders` |
| `IntatisArtifacts` | `MopeliumArtifacts` |
| `IntatisConversation` | `MopeliumConversation` |
| `IntatisPTYLauncher` | `MopeliumPTYLauncher` |
| `IntatisTools` | `MopeliumTools` |
| `IntatisKnowledge` | `MopeliumKnowledge` |
| `IntatisSkills` | `MopeliumSkills` |
| `IntatisPermission` | `MopeliumPermission` |
| `IntatisCurlTransport` | `MopeliumCurlTransport` |
| `IntatisMCP` | `MopeliumMCP` |
| `IntatisMCPStdioGuard` | `MopeliumMCPStdioGuard` |
| `IntatisMCPStdio` | `MopeliumMCPStdio` |
| `IntatisAgentKernel` | `MopeliumAgentKernel` |
| `IntatisCowork` | `MopeliumCowork` |
| `IntatisMultimodal` | `MopeliumMultimodal` |
| `IntatisSharedUI` | `MopeliumSharedUI` |

项目自有 `Intatis*` Swift/C/Rust 类型、文件、include guard、bundle/resource accessor 和测试类同步改为 `Mopelium*`。不为旧模块建立平行 shim target；确有外部协议兼容需要时，只在最窄 decoder/alias 边界保留旧 raw value。

## 4. Canonical 路径与配置映射

| 旧 identity | 新 canonical identity |
|---|---|
| `~/Library/Application Support/Intatis` | `~/Library/Application Support/Mopelium` |
| `~/.config/intatis/` | `~/.config/mopelium/` |
| `~/.local/share/intatis/` | `~/.local/share/mopelium/` |
| `intatis.json` / `intatis.jsonc` | `mopelium.json` / `mopelium.jsonc` |
| `intatis` CLI config/auth | `mopelium` CLI config/auth |
| `.intatis/` workspace state | `.mopelium/` |
| `.intatis/git-worktrees/` | `.mopelium/git-worktrees/` for new worktrees |
| `.intatis/browser/` | `.mopelium/browser/` |
| `.intatis-rag-*` | `.mopelium-rag-*` |
| `/private/tmp/intatis-*` | `/private/tmp/mopelium-*` |
| `intatis-rbook-helper` | `mopelium-rbook-helper` |
| `.agents/skills/intatis-skill-creator` | `.agents/skills/mopelium-skill-creator` |

环境变量：所有 project-owned `INTATIS_*` canonical 名改为 `MOPELIUM_*`。旧变量只通过集中式 legacy lookup 读取；新旧同时存在时新变量优先，且新值非法时不得回退旧值。代码、日志和测试不得读取或输出 secret 值。

UserDefaults：所有 project-owned `intatis.*` key 改为 `mopelium.*`。Bundle ID 切换后从旧 suite/domain 做一次性、字段级、secret-free 导入；新 domain 只写新 key，旧 key 保留只读兼容。

Application Support：迁移器必须执行 current-UID、regular/no-follow、single-link、mode、schema 与目标冲突检查；按 session 原子迁移并读回 EventLog/projection。禁止盲目覆盖或双写。

Workspace state：

- browser profile 只有在对应进程已 drain 后才可迁移；
- 已存在 Git linked worktree 不得裸移动目录，必须继续识别旧位置，或通过显式 Git-aware move 单项迁移；
- 新建 browser state、worktree 和 Knowledge store 只使用 `.mopelium*`；
- legacy `.intatis*` 继续在 deny/secret/managed-store floor 中受保护，不能因新路径加入而失去安全拦截。

## 5. Canonical 协议与 registry identity

新 session / 新配置只发出以下 Mopelium identity；旧值仅兼容解码：

| 旧 identity | 新 identity |
|---|---|
| `intatis.standard.v7` | `mopelium.standard.v8` |
| `intatis.cowork.v7` | `mopelium.cowork.v8` |
| `intatis.deterministic-policy.v1` | `mopelium.deterministic-policy.v1` |
| `__intatis_authorization_context` | `__mopelium_authorization_context` |
| `intatis:siliconflow-v1` | `mopelium:siliconflow-v1` |
| `intatis:cohere-v2` | `mopelium:cohere-v2` |
| `intatis:legacy-openai-wire` | `mopelium:legacy-openai-wire` |
| `urn:intatis:*` | `urn:mopelium:*` for newly generated values |

Sidecar 迁移必须遵守 strict schema：同一 provider generation 只允许一个 reserved field。新 v8 registry 使用 `__mopelium_authorization_context`；旧 v7 durable generation 继续解释旧字段。宿主按 exact tool snapshot/registry generation 验证后归一到同一内部结构，mixed/duplicate/missing/malformed/secret-bearing 一律在 permission lifecycle 前 fail closed。

历史 `events.jsonl` 不重写。任何包含旧 raw value 的 durable event/config 都通过 additive decoder/normalizer 读取；新 encoder/template 永不重新生成旧值。

## 6. 发行与 provenance 边界

- shipping App、executable、ZIP、DMG、staging、recovery 和 diagnostics 改用 Mopelium identity。
- 新 release recovery 使用 `.mopelium/release-recovery`；旧 Intatis signed submission/bundle 不能冒充 Mopelium 恢复输入，也不得因身份切换重复提交。
- document runtime release spec、helper binary、bundle paths、hash/SBOM/license/signature inventory 随实际文件身份更新；没有双架构签名 roots 和 clean-machine 证据时不得声称完成发行。
- `SNAPSHOT.md` 的 Intatis 来源、旧 commit、旧安装/公证事实、dated reports、第三方许可证和 upstream 名称保持历史真实性。
- `NOTICE.md` 的当前产品主体改为 Mopelium，同时明确当前代码基线来自 `SNAPSHOT.md` 固定的 Intatis 来源；不得删除或伪造 provenance。

## 7. 执行清单

### A. 权威合同

- [x] 记录用户确认的唯一 macOS Bundle ID、无 iOS 产品和删除 App Store target 决策。
- [x] 更新 `AGENTS.md`、产品方向、分发、版本、当前状态、项目地图、架构、禁区、测试和 AI 配置合同。
- [x] 把 `docs/NEXT_TARGET.md` 改为本次单一迁移目标；任务完成后删除或换成下一目标。

### B. 构建图与源码命名

- [x] 原位重命名 package/project/app/CLI/module/internal/test targets 和目录。
- [x] 更新所有 Swift imports、project-owned `Intatis*` 类型/文件与 C include guard。
- [x] 重命名 icon、entitlements、resource bundle、helper 和生成工程输入。
- [x] 删除 iOS App target/tree/reference metadata。
- [x] 删除 Mac App Store target/entitlements/dead conditional source。

### C. 数据、配置与 workspace

- [x] 新增集中式 Mopelium canonical config/path/defaults identity。
- [x] 新增有界 legacy Intatis config/env/defaults/Application Support 读取和一次性迁移。
- [x] 新写入只落 Mopelium；新 canonical 值非法时 fail closed。
- [x] `.mopelium` browser/worktree/Knowledge 路径接线，并继续保护 legacy config/Knowledge deny floor。
- [ ] 旧 browser profile 与 Knowledge publication 的自动迁移需各自 owner/lock/drain 方案；现阶段明确不做裸目录移动。已有 `.intatis/git-worktrees` 可按 Git metadata 安全识别，新建只用 `.mopelium`。

### D. 协议与权限

- [x] registry identity 推进为 Mopelium v8。
- [x] permission sidecar 改为 `__mopelium_authorization_context`；旧 v7 durable strings 只可解码/审计，不经 alias 获得 live authorization。
- [x] adapter/URN/diagnostic/MCP identity 新写 Mopelium、旧值只解码。
- [x] 证明 EventLog、permission correlation、lease、durable ticket 和 recovery 语义未改变。

### E. 发行与文档

- [x] 更新 Makefile、XcodeGen、version gate、release/validator/watchdog/Linux CLI 脚本。
- [x] 更新 App/binary/DMG/ZIP/recovery/document-runtime identity。
- [x] 更新 README、NOTICE、ThirdPartyNotices 中的当前项目表述，同时保留历史 provenance。
- [x] 增加 active-identity 审计：旧名只允许显式 legacy/history/provenance allowlist。

### F. 验证

- [x] `git diff --check` 与工作树范围审计。
- [x] `swift build --disable-automatic-resolution`。
- [x] 受影响 focused suites。
- [x] 完整 `swift test --disable-automatic-resolution` 跑到终点并单列两个既有 retry-boundary 冲突；仅跳过这两个冲突后的完整 command 退出 0。
- [x] `xcodegen generate` 与 Mopelium 版本一致性门。
- [x] `MopeliumMac` unsigned Debug 和 universal Release build。
- [x] 最终 App 读回 `0.10 (49)`、Bundle ID `com.Vita0818.Mopelium`、executable `MopeliumMac` 与双架构。
- [x] iOS target、App Store target、App Sandbox entitlement 和本地 agent 安全边界 inventory。
- [x] release/validator shell syntax 与 document runtime spec 静态验证。
- [x] 不运行真实 provider、真实 credential、签名、公证、上传或发布，除非用户另行明确授权。

## 8. 完成定义

本迁移只有在以下条件同时成立时才可标记完成：

1. 当前构建图、源码路径、project-owned 类型、命令和新 runtime 写入均以 Mopelium 为 canonical identity；
2. 唯一 Xcode App target 是 `MopeliumMac`，Bundle ID 为 `com.Vita0818.Mopelium`；
3. iOS App 和遗留 Mac App Store target 已删除；
4. 旧 Intatis session/config/protocol 可由有界兼容路径读取，且不会触发双写、权限扩大或历史重写；旧 browser/Knowledge/worktree state 不裸移动并有明确安全处置；
5. EventLog、permission、lease、workspace、sandbox、secret 与 lifecycle 不变量通过回归；
6. active-identity 审计中的每个残留旧名都属于显式 legacy/history/provenance allowlist；
7. 文档与当前源码事实一致，验证结果和未完成外部门如实记录。
