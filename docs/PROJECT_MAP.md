# PROJECT_MAP

最近自查日期：2026-06-25

本文描述当前仓库结构。判断依据来自 `Package.swift`、源码、测试文件和 `.gitignore`。

## 目录结构总览

```text
Mopelium/                       (/Users/vita/Vitemis/Virgo/Mopelium/)
├── .git/                       Git 仓库（main，单 commit v0.1，remote github.com/Vita0818/Mopelium）
├── .gitignore                  忽略 .build/.swiftpm/Package.resolved/DerivedData/.DS_Store/.env/*.env/secrets.json
├── Apps/
│   └── mopelium-cli/Sources/
│       └── main.swift          CLI 入口（@main struct MopeliumCLI）
├── Packages/
│   ├── MopeliumCore/Sources/
│   │   ├── CLIConfig.swift     配置模型 + 解析
│   │   ├── MopeliumError.swift 错误枚举
│   │   └── Terminal.swift      stdout/stderr/truncated 工具
│   └── MopeliumProviders/Sources/
│       ├── ChatTypes.swift     ChatMessage/ChatRequest/ChatChunk/ChatResponse/ChatProvider 协议
│       ├── OpenAICompatibleProvider.swift  OpenAI 兼容 provider 实现
│       └── SSEParser.swift     SSE 事件解析器
├── Tests/
│   ├── MopeliumCoreTests/
│   │   └── ConfigTests.swift   4 个配置测试
│   └── MopeliumProvidersTests/
│       └── SSEParserTests.swift  3 个 SSE 解析测试
└── Package.swift               SwiftPM manifest（swift-tools 5.9，macOS 13）
```

## Target / 模块

| Target | 类型 | 依赖 | 入口/源 | 职责 |
|---|---|---|---|---|
| `MopeliumCore` | library | — | `Packages/MopeliumCore/Sources/` | 配置模型/解析、错误类型、终端 I/O 工具 |
| `MopeliumProviders` | library | `MopeliumCore` | `Packages/MopeliumProviders/Sources/` | Chat 协议类型 + OpenAI 兼容 provider + SSE 解析 |
| `MopeliumCLI` | executable | `MopeliumCore`, `MopeliumProviders` | `Apps/mopelium-cli/Sources/main.swift` | CLI 入口（product 名 `mopelium`） |
| `MopeliumCoreTests` | test | `MopeliumCore` | `Tests/MopeliumCoreTests/` | 配置测试 |
| `MopeliumProvidersTests` | test | `MopeliumProviders` | `Tests/MopeliumProvidersTests/` | SSE 解析测试 |

- 平台：macOS 13（`.macOS(.v13)`）
- Swift tools：5.9
- **零外部依赖**（无 `.package(url:...)`；仅 Foundation + 条件 `FoundationNetworking`/`Darwin`）

## 关键文件

- 入口：`Apps/mopelium-cli/Sources/main.swift`（`@main struct MopeliumCLI`，`static func main() async`）
- 配置：`Packages/MopeliumCore/Sources/CLIConfig.swift`（`CLIConfig`/`CLIConfigOverrides`/`ResolvedCLIConfig`/`CLIConfigField`/`CLIConfigStore`）
- 错误：`Packages/MopeliumCore/Sources/MopeliumError.swift`（`MopeliumError` enum）
- 终端：`Packages/MopeliumCore/Sources/Terminal.swift`（`out`/`errOut`/`truncated`）
- Chat 模型：`Packages/MopeliumProviders/Sources/ChatTypes.swift`（`ChatMessage`/`ChatRequest`/`ChatChunk`/`ChatResponse`/`ChatProvider` 协议）
- Provider：`Packages/MopeliumProviders/Sources/OpenAICompatibleProvider.swift`（`OpenAICompatibleProvider: ChatProvider`）
- SSE：`Packages/MopeliumProviders/Sources/SSEParser.swift`（`SSEParserEvent`/`SSEParser`）
- 测试：`Tests/MopeliumCoreTests/ConfigTests.swift`（4 tests）、`Tests/MopeliumProvidersTests/SSEParserTests.swift`（3 tests）

## 生成物 / 产物

- 构建产物：`.build/`（含可执行 `mopelium`）
- 用户配置：`~/.config/mopelium/config.json`（JSON，`chmod 0600`，atomic 写）

## 脚本与工具

无辅助脚本。仅 SwiftPM 标准命令。

## 不确定项

- **无 README/LICENSE**：项目身份（"Mopelium" 名字来源/含义）未文档化，全从代码推断。
- **`selftest` 字符串**：`main.swift` 打印 `Mopelium selftest: OK`，与产品名一致（区别于 Councis 的 `Mopelium selftest` 残留）。
