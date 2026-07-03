# TESTING

最近自查日期：2026-06-25

## 环境

- 操作系统 / 平台：macOS 13+（`Package.swift` `.macOS(.v13)`）。非 Apple 平台可编译但 stream/complete 运行时抛错。
- 工具链版本：Swift 5.9（`Package.swift:1` `swift-tools-version:5.9`）
- 依赖管理：SwiftPM。**零外部依赖**（仅 Foundation + 条件 `FoundationNetworking`/`Darwin`）。
- 凭据 / 配置：
  - API key：环境变量（默认 `MOPELIUM_API_KEY`，可经 `api_key_env` 配置改名）
  - 配置文件：`~/.config/mopelium/config.json`（`chmod 0600`，atomic 写）
  - 无 Keychain 集成

## 构建

```sh
swift build                 # Debug
swift build -c release      # Release，产物 .build/release/mopelium
```

无 Xcode 工程、无 xcodegen、无 Makefile。纯 SwiftPM。

## 测试

```sh
swift test                                      # 全部 7 个测试
swift test --filter MopeliumCoreTests           # 4 个配置测试
swift test --filter MopeliumProvidersTests      # 3 个 SSE 测试
swift test --filter MopeliumCoreTests/ConfigTests/testRejectsAPIKeyConfigField
```

### 测试覆盖

**`Tests/MopeliumCoreTests/ConfigTests.swift`（4 tests）：**
- `testDefaultConfigCanResolveWithoutFileOrEnv` — 无文件/env 解析出全部默认；`apiKeyLoaded` false
- `testEnvironmentOverridesFileConfig` — 写文件 config，env 覆盖文件值；`apiKeyLoaded` true
- `testRejectsAPIKeyConfigField` — `writableField(named:"api_key")` 抛含 "Refusing to store API keys" 错误
- `testSetWritesNonSecretConfig` — `set("base_url"|"model"|"api_key_env")` 往返读写
- 用 `FileManager.default.temporaryDirectory` 下随机临时目录

**`Tests/MopeliumProvidersTests/SSEParserTests.swift`（3 tests）：**
- `testParsesOpenAIContentDeltasAndDone` — 单次 consume + flush → "Hello" + `.done`
- `testReassemblesAcrossArbitraryChunks` — 同样本按 5 字节切分喂入 → 仍 "Hello" + `.done`（验证 buffer 重组）
- `testIgnoresCommentsAndEmptyDeltas` — `: keep-alive` 注释与 `{"delta":{}}` 跳过 → 仅 `[.content("ok"), .done]`

### 内置 selftest（非单测）

```sh
swift run mopelium selftest
# 验证: 默认 config 解析、SSE 解析器对内联 "Hello" 样本、api_key 写入被拒
# 打印: Mopelium selftest: OK
```

## Lint / Format

仓内无 lint/format 配置。`UNKNOWN` — 是否有 SwiftFormat/SwiftLint 需后续确认。建议至少 `swift build` 通过。

## 手动验证矩阵

| 场景 | 步骤 | 预期 | 状态 |
|---|---|---|---|
| 构建 | `swift build` | 成功，产物 `.build/debug/mopelium` | UNKNOWN（本轮未跑） |
| 全测 | `swift test` | 7 个测试全过 | UNKNOWN（本轮未跑） |
| selftest | `swift run mopelium selftest` | `Mopelium selftest: OK` | UNKNOWN |
| help | `swift run mopelium help` | 打印用法 | UNKNOWN |
| 流式 chat | `MOPELIUM_API_KEY=sk-... swift run mopelium ask "你好"` | 流式输出回答 | UNKNOWN（需 key） |
| 非流式 chat | `MOPELIUM_API_KEY=sk-... swift run mopelium ask --no-stream "你好"` | 完整输出回答 | UNKNOWN（需 key） |
| config show | `swift run mopelium config show` | JSON 输出当前配置 | UNKNOWN |
| config set | `swift run mopelium config set base_url https://...` | 写入 config.json（0600） | UNKNOWN |
| 拒绝写 key | `swift run mopelium config set api_key sk-...` | 报错 "Refusing to store API keys" | UNKNOWN |
| env 覆盖 | `MOPELIUM_MODEL=gpt-4o swift run mopelium config show` | model 显示 gpt-4o | UNKNOWN |
| HTTP 错误 | 用错误 key 跑 ask | 抛 `.httpStatus(401, ...)`，stderr 输出 | UNKNOWN |

## 验证边界声明

- 文档任务：至少运行 `git diff --check` 与 `git status --short`；**未运行构建/测试**，须在最终报告中声明。
- 代码任务：`swift test` 覆盖 `CLIConfig` 与 `SSEParser`；`OpenAICompatibleProvider` HTTP 路径无自动化测试（无网络 mock），须手动验证。
- 本目录文档为只读分析产出，未运行 `swift build`/`swift test`。

## 常见问题

- **无 multi-turn**：`runAsk` 每次只发单条 user message，无会话历史持久化。若需多轮对话须另行实现。
- **非 Apple 平台**：stream/complete 用 `#if canImport(Darwin)` 守卫，Linux/Windows 编译通过但运行时 chat 抛错。
- **HTTPS 未强制**：base URL 校验仅要求 scheme 非空，`http://` 端点会明文传 key。手动测试第三方端点注意。
- **无请求超时配置**：依赖 `URLSession.shared` 默认超时。
- **API key 在进程环境**：经 env 传 key 会出现在进程列表，标准 tradeoff。
