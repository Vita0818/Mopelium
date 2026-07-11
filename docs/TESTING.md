# TESTING

最近自查日期：2026-07-08

## 环境

- macOS 13+。
- Swift tools version：5.9。
- 依赖：零第三方 Swift package；使用 Foundation、SwiftUI/AppKit、可用时使用 PDFKit。
- Browser profile 工具运行时需要宿主环境提供 Node.js，并优先使用 Playwright；Playwright 不可用时可 fallback 到已安装 Chrome/Edge/Chromium 的 CDP。
- API key：默认从 `MOPELIUM_API_KEY` 读取，可通过 `api_key_env` 修改 env 名。

## 常规命令

```sh
swift build
swift test
swift run mopelium selftest
xcodebuild -project Mopelium.xcodeproj -scheme MopeliumMac -configuration Debug -derivedDataPath .build/XcodeDerivedData build
```

Codex 沙盒内可能需要把 module cache 放进仓库，并禁用 SwiftPM 内层 sandbox：

```sh
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift build --disable-sandbox
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift test --disable-sandbox
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift run --disable-sandbox mopelium selftest
```

## 自动测试覆盖

`MopeliumCoreTests/ConfigTests.swift`：

- 默认配置解析。
- env 覆盖 config 文件。
- API key config field 拒写入。
- 非 secret config set/read round trip。

`MopeliumProvidersTests/SSEParserTests.swift`：

- OpenAI content delta + `[DONE]`。
- 任意 chunk 切分重组。
- 注释与空 delta 跳过。

Core/Providers 子集当前共 7 个 XCTest 测试。

`MopeliumToolsTests/MopeliumToolsTests.swift`：

- file / patch / path confinement。
- shell / git / staged patch / worktree 工具。
- PDF 读取与页面抽取。
- document image reconstruction / LaTeX / image generation 注入后端。
- `web_fetch` schema、HTTP 限制与 opt-in 本地 HTTP smoke。
- browser fake-shell/CDP wrapper 覆盖 profile state/history、metadata-only inventory、profile delete confirmation、navigate/search/snapshot/handoff/reload/back/forward/click/type/submit/select-option/press-key/scroll/wait/screenshot/upload/download/downloads、changedFiles 和敏感输入拒绝。
- 真实浏览器、真实本地 HTTP、真实并发 profile smoke 通过环境变量显式开启，默认跳过。

`MopeliumAgentTests/MopeliumAgentTests.swift`：

- fake provider 驱动 agent loop 执行 `write_file` 并将 observation 回灌第二轮模型请求。
- read-only policy 下拒绝 write 工具，且不创建文件。

当前总计约 72 个 XCTest；默认环境下真实浏览器/本地 HTTP smoke 仍通过环境变量 opt-in。

## v0.4 手动验证矩阵

| 场景 | 步骤 | 预期 |
|---|---|---|
| Mac app 构建 | `swift build` 或沙盒命令 | `MopeliumMac` target 编译通过 |
| CLI selftest | `swift run mopelium selftest` | `Mopelium selftest: OK` |
| 文本文档读取 | Mac app `Sources` -> `Choose File` 选择 UTF-8 文本/Markdown | 预览正文，可复制 context |
| 文件夹浏览 | `Sources` -> `Browse Folder` | 列出支持的文档，可点 `Read` |
| PDF 读取 | 选择有可提取文字的 PDF | 显示页文本；扫描件可能显示无可提取文本 |
| 敏感文件拒读 | 选择 `.env` / `.pem` / `secrets.json` | UI 报拒读 |
| Web 搜索 | 输入 query -> `Search` | 返回 DuckDuckGo HTML 解析结果 |
| Web 抓取 | 输入 `https://example.com` -> `Fetch` | 显示 HTTP status、title、正文和 links |
| Full tool console | `Sources` -> `Choose Workspace` -> 选择工具 -> 编辑 JSON -> `Run Tool` | 显示 observation；写入类工具显示 changed files |
| Browser profile 工具 | 选择 workspace 后运行 `browser_diagnostics` / `browser_search` / `browser_navigate` 等 | `.mopelium/browser` 中维护 profile/state/history/download metadata |
| Browser handoff/登录态 | 设置 opt-in smoke 或人工运行 `browser_handoff` | 打开有界 headed profile，超时后回写 state/history |
| Chat 回归 | 设置 API key 后在 `Chat` 发送消息 | 使用配置的 provider/model 返回结果 |
| CLI AI 工具调用 | 设置 API key 后运行 `mopelium ask --tools <workspace> "..."` | 模型可通过 `ToolRegistry.standard()` 调用允许的 workspace 工具，工具事件输出到 stderr |
| Mac Chat AI 工具调用 | `Chat` -> `Tools` -> `Workspace` -> 发送需要读取/网页访问/浏览器操作的问题 | assistant bubble 显示 tool call/result trace，并继续生成最终回答 |

## 本轮验证记录

2026-07-08 本轮已运行：

```sh
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift build --disable-sandbox
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift build --disable-sandbox --build-tests
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift run --disable-sandbox mopelium selftest
.build/arm64-apple-macosx/debug/mopelium help
xcodegen generate
xcodebuild -project Mopelium.xcodeproj -scheme MopeliumMac -configuration Debug -derivedDataPath .build/XcodeDerivedData build
```

结果：SwiftPM 构建通过；测试 target 编译通过；增强后的 CLI selftest 输出 `Mopelium selftest: OK`，其中包含无网络 agent loop 工具调用回灌自测；CLI help 已显示 `ask --tools` 参数；XcodeGen 生成成功；`MopeliumMac` Xcode Debug build 通过。

本轮 `swift test --disable-sandbox --filter SSEParserTests`、`swift test --disable-sandbox --filter MopeliumAgentTests` 和受控精简环境 `xcrun xctest` 都在 bundle 构建/载入后卡住；请求提权重跑 `swift test` 被策略拒绝。因此本轮未能声明完整 XCTest 通过，需要在用户本机正常测试环境复跑。

未运行真实联网 Web 搜索/抓取、真实浏览器 smoke、Mac UI 点击、PDF 文件人工验证、真实 API key chat E2E、真实模型 tool-calling E2E。默认跳过的 opt-in smoke 包括 `MOPELIUM_LOCAL_HTTP_SMOKE=1`、`MOPELIUM_REAL_BROWSER_SMOKE=1`、`MOPELIUM_REAL_BROWSER_HANDOFF_SMOKE=1`、`MOPELIUM_REAL_BROWSER_CONCURRENCY_SMOKE=1`。
