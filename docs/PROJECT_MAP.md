# PROJECT_MAP

最近自查日期：2026-07-08

本文描述当前仓库结构。判断依据来自 `Package.swift`、`project.yml`、当前源码、测试文件和工作区状态。

## 目录结构总览

```text
Mopelium/                                      (/Users/vita/Vitemis/Virgo/Mopelium/)
├── Apps/
│   ├── MopeliumMac/
│   │   ├── Info.plist
│   │   └── Sources/
│   │       ├── MopeliumMacApp.swift          SwiftUI app 入口
│   │       ├── MopeliumMacRootView.swift     NavigationSplitView + section routing
│   │       ├── MopeliumResearchScreen.swift  Chat UI + API 接入
│   │       ├── MopeliumSourcesScreen.swift   v0.4 文档阅读 + Web 搜索/抓取
│   │       ├── MopeliumTasksScreen.swift     任务 surface
│   │       ├── MopeliumSettingsScreen.swift  配置展示
│   │       ├── MopeliumSidebar.swift         侧边栏
│   │       ├── MopeliumComponents.swift      可复用 UI 组件
│   │       ├── MopeliumDesign.swift          theme/type tokens
│   │       └── MopeliumMockData.swift        静态示例数据
│   └── mopelium-cli/Sources/
│       └── main.swift                        CLI 入口
├── Packages/
│   ├── MopeliumCore/Sources/
│   │   ├── CLIConfig.swift                   配置模型 + 解析
│   │   ├── MopeliumError.swift               错误枚举
│   │   └── Terminal.swift                    stdout/stderr/truncated
│   ├── MopeliumProviders/Sources/
│   │   ├── ChatTypes.swift                   Chat 数据模型与协议
│   │   ├── OpenAICompatibleProvider.swift    OpenAI-compatible provider
│   │   ├── ToolCallingTypes.swift            tool-calling 数据模型与协议
│   │   └── SSEParser.swift                   SSE 解析器
│   ├── MopeliumAgent/Sources/
│   │   ├── MopeliumAgentLoop.swift           AI 工具调用循环、policy、observation 回灌
│   │   └── OpenAICompatibleToolCallingProvider.swift
│   │                                           OpenAI-compatible tools stream provider
│   └── MopeliumTools/Sources/
│       ├── ToolProtocol.swift                工具协议、schema、registry
│       ├── ToolSupport.swift                 工具错误、JSONValue、side effect
│       ├── PathConfinement.swift             workspace 路径围栏
│       ├── FileTools.swift                   read/list/search/write file
│       ├── PatchTool.swift                   unified diff apply
│       ├── ShellGit.swift                    shell + git/worktree/patch tools
│       ├── DocumentMediaTools.swift          PDF/文档媒体/LaTeX/生图工具
│       └── BrowserTools.swift                web_fetch + browser profile/interaction
├── Tests/
│   ├── MopeliumCoreTests/ConfigTests.swift
│   ├── MopeliumProvidersTests/SSEParserTests.swift
│   ├── MopeliumToolsTests/MopeliumToolsTests.swift
│   └── MopeliumAgentTests/MopeliumAgentTests.swift
├── Mopelium.xcodeproj/                       Xcode 工程（当前工作区已有）
├── Package.swift                             SwiftPM manifest
├── project.yml                               XcodeGen 配置
└── docs/
```

## Products / Targets

| Product / Target | 类型 | 依赖 | 职责 |
|---|---|---|---|
| `MopeliumCore` | library | - | 配置、错误、终端工具 |
| `MopeliumProviders` | library | `MopeliumCore` | Chat 协议、OpenAI-compatible HTTP、SSE |
| `MopeliumTools` | library | - | Intatis 迁移工具面：file/patch/shell/git/PDF/browser |
| `MopeliumAgent` | library | Core, Providers, Tools | AI tool-calling loop、OpenAI-compatible tool-call stream parser/provider |
| `mopelium` / `MopeliumCLI` | executable | Core, Providers, Tools, Agent | CLI chat/config/selftest，`ask --tools` AI 工具模式 |
| `MopeliumMac` | executable / app | Core, Providers, Tools, Agent | macOS SwiftUI UI，Chat 可启用 AI 工具调用 |
| `MopeliumCoreTests` | test | Core | config tests |
| `MopeliumProvidersTests` | test | Providers | SSE parser tests |
| `MopeliumToolsTests` | test | Tools | 迁移工具面 tests |
| `MopeliumAgentTests` | test | Agent, Providers | agent loop fake-provider tests |

平台：macOS 13+。Swift tools：5.9。外部依赖：无第三方 package。

## v0.4 关键文件

- `Apps/MopeliumMac/Sources/MopeliumSourcesScreen.swift`：本地文档读取、文件夹浏览、Web 搜索、HTTP(S) 页面抓取、正文/链接抽取、copy context，以及 full Intatis tool console。
- `Packages/MopeliumAgent/Sources/MopeliumAgentLoop.swift`：将模型 `tool_calls` 转为 `MopeliumTools` 执行，执行结果作为 tool observation 回灌模型；按 side effect policy 控制工具暴露和执行。
- `Packages/MopeliumAgent/Sources/OpenAICompatibleToolCallingProvider.swift`：OpenAI-compatible Chat Completions `tools` 请求体编码、SSE tool-call delta 拼接、finish_reason 处理和工具参数 JSON 校验。
- `Packages/MopeliumProviders/Sources/ToolCallingTypes.swift`：provider 与 agent 共享的 `ToolSpec` / `ToolCall` / `ToolChatMessage` / `ToolChatRequest` / `ToolChatChunk`。
- `Packages/MopeliumTools/Sources/ToolProtocol.swift`：`Tool` / `ToolRegistry` / `ToolContext` / schema 描述；`ToolRegistry.standard()` 当前暴露 53 个工具。
- `Packages/MopeliumTools/Sources/BrowserTools.swift`：`web_fetch` 与 `browser_*` profile、导航、快照、handoff、点击、输入、提交、选择、按键、滚动、等待、截图、上传、下载、搜索。
- `Packages/MopeliumTools/Sources/DocumentMediaTools.swift`：`read_pdf`、`edit_pdf_pages`、`reconstruct_document_image`、`compile_latex`、`generate_image`。
- `Packages/MopeliumTools/Sources/ShellGit.swift` / `PatchTool.swift` / `FileTools.swift`：shell、git、worktree、patch 与 file tools。
- `Apps/MopeliumMac/Sources/MopeliumResearchScreen.swift`：Mac chat 主链路，使用 `CLIConfigStore` 和 `OpenAICompatibleProvider`；启用 Tools 后使用 `MopeliumAgentLoop`。
- `Apps/MopeliumMac/Sources/MopeliumComponents.swift` / `MopeliumDesign.swift`：当前 Mac app 视觉系统。
- `Apps/mopelium-cli/Sources/main.swift`：CLI 入口、`ask --tools`、增强 selftest。
- `Packages/MopeliumCore/Sources/CLIConfig.swift`：配置优先级与 API key env 读取。
- `Packages/MopeliumProviders/Sources/OpenAICompatibleProvider.swift`：HTTP 请求、状态校验、stream 取消。
- `Packages/MopeliumProviders/Sources/SSEParser.swift`：SSE 行导向解析。

## 生成物 / 外部状态

- SwiftPM 构建产物：`.build/`。
- Codex 沙盒内构建使用仓库内 `.build/module-cache` 避免写用户级 clang cache。
- Xcode 构建产物：本轮验证使用 `.build/XcodeDerivedData`。
- 用户配置文件：`~/.config/mopelium/config.json`，由 Core 逻辑管理，权限仍为 `0600`。
- Mac app 的用户选择文件/文件夹权限来自运行时 `NSOpenPanel`，不在仓库内持久化。
- Browser 工具运行时数据：所选 workspace 内 `.mopelium/browser/`，包含 profile/state/history/download metadata/downloads；不得写入仓库文档。
