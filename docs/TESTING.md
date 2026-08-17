# TESTING

文档状态：当前验证矩阵
最近核对：2026-08-17
产品基线：v0.10（build 49）

历史测试数字和 pre-migration Intatis target 结果保留在 Git 历史与 dated reports，不替代当前 Mopelium working tree 验证。

## 产品边界

- 当前 Apple 构建环境：Xcode 27 / Swift 6.x / XcodeGen；
- 唯一 App target：Developer ID/direct-distribution `MopeliumMac`；
- Bundle ID：`com.Vita0818.Mopelium`；
- 不存在 iOS 或 Mac App Store target/scheme/release gate；
- SwiftPM 中的 permission、workspace、Seatbelt、Linux bwrap/guard、EventLog 与 durable execution 仍是安全门。

## 版本与工程一致性

```sh
xcodegen generate
scripts/check-version-consistency.sh
# 或 make version
```

必须同时满足：

- `project.yml`：`MARKETING_VERSION=0.10`、`CURRENT_PROJECT_VERSION=49`；
- `Apps/MopeliumMac/Info.plist`：`0.10 (49)`；
- `Mopelium.xcodeproj`：相同版本且只有 `MopeliumMac` App scheme；
- README、文档入口、CURRENT_STATE、PROJECT_MAP：相同基线；
- 最终 App：版本 `0.10 (49)`、Bundle ID `com.Vita0818.Mopelium`、executable `MopeliumMac`。

## SwiftPM 基线

```sh
swift package dump-package
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
```

外层 managed sandbox 若阻止 nested Seatbelt、process spawn、loopback 或 compiler cache，应在获准真实 host 环境重跑；不得把环境失败改成产品失败，也不得把 skip 冒充通过。

模块级 focused suites 使用当前 target 名：

```sh
swift test --filter MopeliumCoreTests
swift test --filter MopeliumProtocolTests
swift test --filter MopeliumProvidersTests
swift test --filter MopeliumConversationTests
swift test --filter MopeliumToolsTests
swift test --filter MopeliumPermissionTests
swift test --filter MopeliumAgentKernelTests
swift test --filter MopeliumCoworkTests
swift test --filter MopeliumSharedUITests
swift test --filter MopeliumCLITests
```

## 内部身份迁移专项

至少运行：

```sh
swift test --filter ProductIdentityMigrationTests
swift test --filter CLIConfigRuntimeBudgetTests
swift test --filter MopeliumProvidersTests/testLegacyProductAdapterNamesCanonicalizeToMopelium
swift test --filter WorkspaceLeaseTests
swift test --filter MopeliumPermissionTests/testSecretScannerPaths
swift test --filter AuthorizationSidecarTests
swift test --filter ToolRegistryLeaseTests
```

必须证明：

- Application Support 只有 canonical 缺失且 legacy 安全时才在稳定锁内原子 rename；device/inode 保真；dual roots 与 symlink fail closed；EventLog bytes 不变；
- Bundle ID 变更后的 UserDefaults 只按 allowlist 导入且不覆盖 canonical key；
- `MOPELIUM_*`/Mopelium config 优先，旧 `INTATIS_*`/Intatis paths 仅在 canonical 缺失时读取；
- legacy secret/config paths 继续进入 SecretScanner 与 terminal deny floor；
- old adapter IDs 规范化并只重新编码 Mopelium，unknown adapter byte-exact；
- registry 为 `mopelium.standard.v8` / `mopelium.cowork.v8`；
- sidecar 为 `__mopelium_authorization_context`，strict schema 不变量保持；
- old EventLog/registry strings可解码但不能经 alias 获得 live authorization；
- active source/build identities 的旧名残留只在显式 legacy/history/provenance allowlist。

## Cowork automatic permission

```sh
swift test --filter PermissionReviewProtocolTests
swift test --filter AuthorizationSidecarTests
swift test --filter MopeliumPermissionReviewerTests
swift test --filter PermissionReviewControlPlaneTests
swift test --filter AutomaticPermissionReviewTests
swift test --filter DurableMultimodalAgentLoopTests
```

必须覆盖 request-owned schema decoration、strict recursive required/additionalProperties、tool_search deferred children、same-generation sidecar binding、stripped business arguments、transient/durable isolation、correctable missing/malformed/secret failure、manual reserved-field refusal、dedicated host admission、duplicate/recovery/cancel/timeout/provider/persistence fail-closed，以及 reviewer prompt 不含 raw user/history/PDF/image。

真实 provider sidecar smoke 只有用户明确授权 credential/network/cost 后才可运行：

```sh
MOPELIUM_REAL_TOOL_SHAPE_DIAGNOSTIC=1 swift test \
  --filter RealProviderSmokeTests/testRealAgentAuthorizationSidecarShapeWhenEnabled
```

默认 skip 不算真实通过。

## 数据、权限与恢复

涉及 EventLog、projection、workspace bookmark、permission、terminal、Cowork 或 lifecycle 时，至少按范围覆盖：

```text
SessionStateProtocolTests
SessionProjectionStoreTests
PermissionSettlementTransactionTests
PermissionProjectionTests
TurnOutcomeProtocolTests
AgentLoopOutcomeTests
SandboxDenialOutcomeTests
WorkspaceSandboxDenialTests
OrchestrationReliabilityTests
AutomaticPermissionReviewTests
```

必须保持 EventLog append-only/seq/WAL、session.json rebuild、bookmark owner-only binary/no-follow、first-write/first-terminal permission CAS、manual Decline vs Cancel Turn、trusted sandbox startup classification、cancel/drain ordering、fresh seven-event Cowork bootstrap、historical main/reviewer repair与 explicit resume/retry。

## Managed terminal / Git / browser

```sh
swift test --filter TerminalToolsTests
swift test --filter TerminalAgentLoopTests
swift test --filter ShellPermissionTests
swift test --filter WorkspaceSandboxDenialTests
swift test --filter HostedWebSearchToolTests
swift test --filter ProviderHostedWebSearchToolServiceTests
```

必须证明 no raw run_shell、exact owner/session/agent/task/attempt/workspace binding、write_stdin 独立授权、dangerous-command split-input guard、partial-write termination、default-network-deny、process drain、new `.mopelium` worktree/browser paths，以及 legacy `.intatis` paths 不被裸移动或解除保护。

## 文档、图片与 Knowledge

文档链：

```sh
swift build --target MopeliumTools --disable-automatic-resolution
swift test --filter DocumentReadToolSplitTests
swift test --filter DocumentToolContractTests
swift test --filter DocumentInfrastructureTests
swift test --filter PDFNativeDocumentServiceTests
swift test --filter DocumentPythonWriteBackendTests
swift test --filter DocumentFixedBackendsTests
swift test --filter DocumentToolsIntegrationTests
```

图片/多模态：

```sh
swift test --filter ArtifactImageResolverTests
swift test --filter WorkspaceImageToolTests
swift test --filter MopeliumProvidersToolCallingTests
swift test --filter ModelHistory
swift test --filter DurableMultimodalAgentLoopTests
swift test --filter CLIAttachmentTests
```

Knowledge：

```sh
swift build --target MopeliumKnowledge --disable-automatic-resolution
swift test --filter MopeliumKnowledgeTests
swift test --filter KnowledgeModelProviderTests
swift test --filter ModelDrivenKnowledgeAgentLoopTests
swift test --filter TurnGroundingEvidenceRegistryTests
```

真实 document runtime、provider、Knowledge quality/PDF、browser、Git 与 multimodal smoke 全部保持显式 opt-in，不隐式读取凭据、外发资料或消费额度。

## macOS App build

```sh
xcodegen generate

xcodebuild -quiet -project Mopelium.xcodeproj -scheme MopeliumMac \
  -configuration Debug -destination 'platform=macOS' \
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO build

xcodebuild -quiet -project Mopelium.xcodeproj -scheme MopeliumMac \
  -configuration Release -destination 'platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  COMPILER_INDEX_STORE_ENABLE=NO CODE_SIGNING_ALLOWED=NO build
```

构建后必须从最终 bundle 读取：

```sh
plutil -extract CFBundleShortVersionString raw -o - <App>/Contents/Info.plist
plutil -extract CFBundleVersion raw -o - <App>/Contents/Info.plist
plutil -extract CFBundleIdentifier raw -o - <App>/Contents/Info.plist
lipo -archs <App>/Contents/MacOS/MopeliumMac
```

必须为 `0.10`、`49`、`com.Vita0818.Mopelium` 和 `arm64 x86_64`。工程 inventory 必须证明没有 iOS/App Store target 和 App Sandbox entitlement。

## Developer ID 直接分发

静态预检：

```sh
zsh -n scripts/package-macos-release.sh
zsh -n scripts/validate-document-runtime.sh
plutil -convert xml1 -o /dev/null Packages/MopeliumTools/Runtime/document-runtime/release-spec.json
```

正式发行只在用户明确授权且两套 reviewed/signed runtime roots、Developer ID identity、notary profile 和网络均满足时执行：

```sh
MOPELIUM_DOCUMENT_RUNTIME_ARM64_ROOT=<reviewed-root> \
MOPELIUM_DOCUMENT_RUNTIME_X86_64_ROOT=<reviewed-root> \
MOPELIUM_NOTARY_PROFILE=<profile> \
  scripts/package-macos-release.sh
```

脚本必须验证 universal executable、Bundle ID、runtime manifest/hash/SBOM/license/architecture/signature、Hardened Runtime、App/DMG notarization/staple/codesign/Gatekeeper、ZIP/DMG hashes和 clean-machine smoke。任一门槛失败不得发布。

## 当前直接结果

2026-08-17 内部 identity migration 当前直接结果：

- `swift package dump-package`：通过，Mopelium package、15 libraries、3 internal targets、CLI、15 tests、macOS-only platform；
- `swift build --disable-automatic-resolution`：四次通过；只有既有 warning；
- identity/config/adapter/deny-floor/sidecar/registry/target-inventory/Cowork focused command：60 tests、0 failures；
- 原始完整 `swift test --disable-automatic-resolution`：执行到终点、退出 1；只有
  `testOpenAIStreamingDoesNotRetryAfterResponseBytes` 与
  `testOfficialProviderRetryBoundaryStaysInsideOneLogicalGeneration` 两个独立稳定复现的既有 retry-boundary 合同冲突；
- 显式 `--skip` 上述两个冲突后，完整 SwiftPM command 退出 0；opt-in 真实环境 tests 按设计 skipped；
- `xcodegen generate`、版本门、active identity 门：通过；Xcode project 只有 `MopeliumMac` App target；
- `MopeliumMac` unsigned Debug：通过；最终 `0.10 (49)`、Bundle ID `com.Vita0818.Mopelium`、display name Mopelium、arm64 executable；
- `MopeliumMac` unsigned universal Release：通过；最终 executable 为 `x86_64 arm64`；
- release/validator/version/identity/Linux/scheme shell syntax、release-spec plist parse 与 EPUBCheck wrapper hash：通过；
- project-local Skill quick validation/Python compile：通过；rbook helper fmt、7 unit + 2 integration tests：通过；
- 未运行真实 provider、Developer ID 签名、公证、staple、Gatekeeper、安装、上传或发布。

## Release GO 条件

只有 working tree 当前 tests/builds、最终 bundle identity、Developer ID/notarization/staple/codesign/Gatekeeper、NOTICE/resource inventory 和关键真实环境矩阵全部满足，或未完成项有明确风险接受时，才能写 release GO。
