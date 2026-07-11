# CURRENT_STATE

最近一次自查日期：2026-07-08

## 当前真实状态总览

- Mopelium 当前处于 v0.4：SwiftPM + XcodeGen/macOS project 并存，零第三方依赖。
- Product：`MopeliumCore` lib / `MopeliumProviders` lib / `MopeliumTools` lib / `MopeliumAgent` lib / `mopelium` CLI / `MopeliumMac` macOS SwiftUI app。
- CLI 仍保留 OpenAI-compatible Chat Completions 的 `ask` / `config` / `selftest` 能力。
- Mac app 已有 `Chat` / `Tasks` / `Sources` / `Settings` 四个主区域；`Chat` 复用 Core/Providers 真实 API 配置与流式/非流式调用，并可在用户选择 workspace 后让 AI 调用 `MopeliumTools`。
- v0.4 新增 `Sources` 真实能力：本地文档选择、文件夹文档浏览、文本/Markdown/HTML/JSON/CSV/code/PDF 文本读取、DuckDuckGo HTML 搜索、HTTP(S) 页面抓取、正文/链接抽取、复制 source context，并接入从 `/Users/vita/Vitemis/Intatis` 迁移的完整 `MopeliumTools` 工具面。
- `MopeliumTools` 当前标准注册表暴露 53 个工具，覆盖 file / patch / shell / git / PDF / document-media / `web_fetch` / browser profile / browser interaction / screenshot / upload / download / search。
- `MopeliumAgent` 当前提供 AI tool-calling agent loop：OpenAI-compatible `tools` request/stream parser、工具调用执行、observation 回灌、side-effect policy 和 shell/write/destructive 显式开关。

## 已有能力

| 能力 | 入口 / 关键位置 | 自动验证 | 状态 |
|---|---|---:|---|
| CLI streaming / non-streaming chat | `Apps/mopelium-cli/Sources/main.swift` + `OpenAICompatibleProvider` | 间接 | 保留 |
| Mac chat UI | `MopeliumChatScreen` / `MopeliumChatViewModel` | `swift build` | v0.3 起已有 |
| 配置解析与 API key 环境变量读取 | `CLIConfigStore.resolve` / `ResolvedCLIConfig.requireAPIKey` | 4 tests | 通过 |
| API key 拒写入配置 | `CLIConfigStore.writableField` | 1 test + selftest | 通过 |
| SSE 解析 | `SSEParser` | 3 tests + selftest | 通过 |
| 文档阅读 | `MopeliumSourcesScreen.swift` `MopeliumDocumentReader` | `swift build` | v0.4 新增 |
| 文件夹文档浏览 | `MopeliumSourcesViewModel.browseFolder` | `swift build` | v0.4 新增 |
| Web 搜索 | `MopeliumWebLookup.search` | `swift build` | v0.4 新增 |
| Web 页面访问 | `MopeliumWebLookup.fetch` | `swift build` | v0.4 新增 |
| Intatis 工具面迁移 | `Packages/MopeliumTools/Sources/` | 63 tests | v0.4 新增 |
| Browser profile / interaction 工具 | `BrowserTools.swift` + `SourceToolConsoleCard` | fake-shell tests + Xcode build | v0.4 新增 |
| AI 工具调用 | `MopeliumAgentLoop` + `OpenAICompatibleToolCallingProvider` | `swift build` + CLI selftest | v0.4 新增 |
| CLI 工具模式 | `mopelium ask --tools PATH` | help + build | v0.4 新增 |
| Mac Chat 工具模式 | `ChatToolControls` + `MopeliumChatViewModel.send` | SwiftPM/Xcode build | v0.4 新增 |

## v0.4 设计边界

- 顶部 document reader 仍只通过用户选择文件/文件夹触发，不做后台全盘索引。
- 明确拒绝读取 `.env`、`secrets.json`、证书/key 文件，以及文件名看起来像 `private_key` / `api_key` / `access_token` / `password` 的路径。
- PDF 读取依赖 Apple 平台 `PDFKit` 的可提取文本；扫描件 OCR 不在 v0.4 范围。
- 顶部 `Web Lookup` 是无状态 HTTP(S) 搜索/抓取，不读取浏览器 cookies、登录态或 profile 数据。
- `Full Intatis Tool Surface` 必须先选择 workspace，再在该 workspace 内运行工具；文件路径、截图、上传、下载、browser state/history/profile/downloads 均受 `PathConfinement` 限定。
- AI 工具调用运行前必须有用户选择的 workspace；CLI 通过 `--tools PATH` 启用，Mac Chat 通过 `Tools` toggle + `Workspace` 选择启用。默认暴露 readOnly/network/exec 工具但不允许 `run_shell`，write/destructive/shell 需要显式开关。
- Browser 工具把持久 profile/state/history/downloads 放在 workspace 的 `.mopelium/browser/` 下；优先使用 Node.js + Playwright，Playwright 不可用时使用 Node.js `WebSocket` + Chrome DevTools Protocol fallback 到已安装 Chrome/Edge/Chromium。
- `browser_profiles` / `browser_history` / `browser_downloads` 只返回受控 metadata，不读取 cookies、localStorage、profile 数据库或下载内容；`browser_profile_delete` 需要 confirmProfile 精确匹配；`browser_type` 遮蔽输入并拒绝疑似密码/2FA/token/API key 目标。

## 风险 / 未完成

- `MopeliumSourcesScreen.swift` 目前承载 UI、轻量 document/web service 和工具 console；工具核心已拆在 `MopeliumTools`，但 UI 文件后续可再拆分。
- `swift test` runner 在本轮 Codex sandbox 内构建完成后卡住，提权重跑被策略拒绝；本轮以 `swift build`、`swift build --build-tests`、增强后的 CLI selftest、Xcode build 作为自动验证。完整 XCTest 仍需在用户本机正常测试环境复跑。
- 真实模型 tool-calling E2E、真实浏览器 smoke、真实联网搜索/抓取、真实上传/下载、Mac UI 点击、NSOpenPanel 文件选择和第三方网站登录态仍需人工或脱离 sandbox 验证。
- 浏览器工具依赖宿主环境 Node.js 和已安装浏览器；Playwright module / Chrome / Edge 可用性属于运行时环境，不由 SwiftPM 依赖管理。

## 工作区状态说明

本轮开始时工作区已有多处未提交改动，包括 `Apps/MopeliumMac/`、`Package.swift`、`project.yml`、`Mopelium.xcodeproj`、`AGENTS.md`、`docs/AGENTS.md` 等。这些视为用户既有改动，本轮只在其基础上增量修改，没有回退或清理。`Intatis` 仓库仅做只读对照，没有写入。
