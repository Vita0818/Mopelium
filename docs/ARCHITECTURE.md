# ARCHITECTURE

最近自查日期：2026-07-08

## 总体架构

Mopelium 当前由共享 Core/Providers/Tools/Agent、CLI、Mac SwiftUI app 组成。

```text
CLI / Mac UI
  ├─ mopelium CLI: ask / config / selftest
  └─ MopeliumMac: Chat / Tasks / Sources / Settings
        │
        ├─ MopeliumCore
        │   ├─ CLIConfigStore
        │   ├─ ResolvedCLIConfig
        │   └─ MopeliumError / terminal helpers
        │
        ├─ MopeliumProviders
        │   ├─ ChatRequest / ChatMessage / ChatResponse / ChatChunk
        │   ├─ ToolSpec / ToolCall / ToolChatRequest / ToolChatChunk
        │   ├─ OpenAICompatibleProvider
        │   └─ SSEParser
        │
        ├─ MopeliumAgent
        │   ├─ OpenAICompatibleToolCallingProvider
        │   └─ MopeliumAgentLoop / MopeliumAgentToolPolicy
        │
        └─ MopeliumTools
            ├─ Tool / ToolRegistry / ToolContext
            ├─ file / patch / shell / git tools
            ├─ PDF / document-media / LaTeX / image tools
            └─ web_fetch / browser profile / browser interaction tools
```

## Chat 主链路

CLI 和 Mac `Chat` 都复用同一条 provider 链路：

```text
prompt / message history
  -> CLIConfigStore.resolve
  -> ResolvedCLIConfig.requireAPIKey()
  -> OpenAICompatibleProvider(baseURL, apiKey)
  -> ChatRequest(model, messages, stream)
  -> stream: URLSession.bytes + SSEParser
     complete: URLSession.data + OpenAICompleteResponse decode
  -> terminal output or SwiftUI message bubble
```

配置优先级仍为：

```text
CLI overrides > env(MOPELIUM_BASE_URL / MOPELIUM_API_KEY_ENV / MOPELIUM_MODEL / MOPELIUM_STREAM)
> ~/.config/mopelium/config.json > defaults
```

API key 只从 `environment[apiKeyEnv]` 读取；`config set api_key` 仍被拒绝。

## AI 工具调用链路

CLI 和 Mac Chat 现在都有 AI 直接调用工具的路径：

```text
CLI: mopelium ask --tools <workspace> [--allow-write] [--allow-destructive] [--allow-shell]
Mac: Chat -> Tools toggle -> Workspace -> optional Write/Destructive/Shell toggles
  -> CLIConfigStore.resolve
  -> OpenAICompatibleProvider(baseURL, apiKey)
  -> OpenAICompatibleToolCallingProvider(provider)
  -> MopeliumAgentLoop(model, message history, ToolRegistry.standard, workspace, policy)
  -> OpenAI-compatible /chat/completions stream=true with tools
  -> stream tool_calls delta accumulation
  -> execute allowed MopeliumTools tool in ToolContext(workspaceRoot)
  -> append role=tool observation
  -> continue model loop until no tool_calls or maxIterations
```

默认 policy 暴露 readOnly/network/exec 工具，但 `run_shell` 仍需要独立 `allowShellTool`；write/destructive 工具需要用户显式开关。CLI 工具调用事件写到 stderr，正文写 stdout；Mac Chat 将 tool call/result trace 附在 assistant bubble 中。

## Mac App 结构

`MopeliumMacRootView` 使用 `NavigationSplitView`：

- `Chat`：真实聊天 UI，窗口内消息历史保存在内存中；可选择 workspace 后启用 AI 工具调用。
- `Tasks`：任务/触发器 surface，目前没有后台 worker。
- `Sources`：v0.4 source collection + full Intatis tool surface。
- `Settings`：展示 provider/config 状态。

视觉系统集中在：

- `MopeliumDesign.swift`：颜色、状态色、字体 token。
- `MopeliumComponents.swift`：page header、glass card、badge、composer、sidebar row、setting row、empty state。

## Sources v0.4

`MopeliumSourcesScreen.swift` 当前包含三层 source 能力：

```text
Document Reader
  -> NSOpenPanel choose file/folder
  -> MopeliumDocumentReader
       - folder: enumerate supported docs under user-selected folder
       - text-like files: UTF-8 read
       - HTML: strip tags/scripts/styles, decode common entities
       - PDF: PDFKit extractable text
       - max text shown/copyable: 60k chars
       - rejects sensitive env/key/token/cert-looking paths
  -> preview + copy source context

Web Lookup
  -> search(query): DuckDuckGo HTML endpoint
       - parse result anchors/snippets best-effort
  -> fetch(url): URLSession HTTP(S)
       - validates scheme/host
       - User-Agent: Mopelium/0.4
       - reads up to 3MB response bytes
       - HTML text extraction + title + links
       - max page text shown/copyable: 60k chars
  -> preview + page links + copy source context + open in browser

Full Intatis Tool Surface
  -> user chooses a workspace
  -> ToolRegistry.standard()
       - 53 migrated tools
       - file: read_file / list_files / search_text / write_file
       - patch: apply_patch
       - shell: run_shell
       - git: status/diff/stage/commit/patch/worktree tools
       - document-media: read_pdf / edit_pdf_pages / reconstruct_document_image / compile_latex / generate_image
       - web: web_fetch
       - browser: diagnostics/profiles/profile_delete/history/navigate/snapshot/handoff/reload/back/forward/click/type/submit/select_option/press_key/scroll/wait/screenshot/upload_file/download/downloads/search
  -> ToolContext(workspaceRoot)
  -> observation text + changedFiles
```

`MopeliumTools` 是从 `/Users/vita/Vitemis/Intatis/Packages/IntatisTools` 只读对照迁移而来，保留原工具协议、schema、side effect、path confinement、fake-shell/browser test surface，并把 Intatis 命名、路径和运行时目录改为 Mopelium。浏览器工具不内置 Chromium；运行时优先使用 Node.js + Playwright persistent context，Playwright 不可解析时 fallback 到 Node.js 内置 `WebSocket` + Chrome DevTools Protocol 驱动已安装 Chrome/Edge/Chromium。

Browser profile 运行时状态限定在所选 workspace：

```text
.mopelium/browser/
  ├─ profiles/<profile>/
  ├─ state/<profile>.json
  ├─ history/
  └─ downloads/<profile>/
```

## 安全机制

- API key 永不写入 config 文件。
- HTTP provider 非 2xx 必须抛 `.httpStatus`，并只收集响应前缀。
- Streaming `onTermination` 必须取消底层 Task。
- 文档读取仅由用户选择触发，拒读 env/key/token/cert-looking 文件。
- 顶部 Web Lookup 不读取 cookies/localStorage，不使用持久浏览器 profile，不做登录态自动化。
- Browser profile 工具只在用户选择的 workspace 内读写 `.mopelium/browser/`，profile/delete/download/screenshot/upload 均通过路径围栏约束。
- `browser_profiles`、`browser_history`、`browser_downloads` 只返回 metadata；不得读取或输出 cookies、localStorage、profile 数据库、runtime marker 内容或下载文件内容。
- `browser_type` 必须遮蔽本次输入值，并拒绝疑似密码、2FA、token、API key 输入目标。
- Agent loop 的工具 observation 会截断回灌，默认最多 12k characters，避免工具输出无限进入模型上下文。
- Agent loop 默认不允许 `run_shell`、write、destructive；必须由 CLI 参数或 Mac toggle 显式放开。
- 长文档和网页正文均截断显示，避免 UI 和 prompt context 失控。
