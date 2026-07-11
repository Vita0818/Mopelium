# Mopelium 项目常驻上下文

本文件继承 `/Users/vita/Vitemis/AGENTS.md` 中的 Vitemis 通用 Agent 规则。若本文件与通用规则冲突，在不违反系统和用户指令的前提下，以更具体、更严格的项目规则为准。

本文是 AI Agent 每轮进入本仓库时的入口文件。执行任何代码修改、配置修改、构建脚本修改或测试源码修改之前，必须先按顺序阅读并核对下列文档：

0. `/Users/vita/Vitemis/AGENTS.md`
1. `docs/CURRENT_STATE.md`
2. `docs/PROJECT_MAP.md`
3. `docs/ARCHITECTURE.md`
4. `docs/DO_NOT_BREAK.md`
5. `docs/TESTING.md`
6. `docs/NEXT_TARGET.md`（如果存在）

如果文档与源码、工程配置、测试或脚本冲突，必须以当前源码和配置为准，并在最终报告中明确指出冲突位置和采用源码为准的原因。

## 工作目录检查

每轮开始先在项目根目录执行：

```sh
pwd
git rev-parse --show-toplevel
git status --short
```

要求：

- `pwd` 与 `git rev-parse --show-toplevel` 必须指向同一个仓库根目录：`/Users/vita/Vitemis/Virgo/Mopelium`。
- 如果当前目录不是 Git root，停止修改，只报告路径问题。
- 读取 `git status --short` 后，先区分用户已有改动与本轮计划改动；不得覆盖、回退或清理用户已有改动。

## 修改边界

本仓库当前是 SwiftPM + XcodeGen/macOS project 并存的 macOS 13+ Swift 项目，零第三方 package。主要 product/target 为 `MopeliumCore` lib、`MopeliumProviders` lib、`MopeliumTools` lib、`MopeliumAgent` lib、`mopelium` CLI、`MopeliumMac` SwiftUI app，以及 4 个测试 target。

未来常规任务可以按用户要求修改业务源码；但在只要求项目自查或文档更新的任务中，只允许修改：

- `AGENTS.md`
- `docs/` 下的项目说明文档

除非用户明确要求，不要修改：

- `Apps/mopelium-cli/Sources/`（`main.swift`）
- `Apps/MopeliumMac/Sources/`（Mac SwiftUI app）
- `Packages/MopeliumCore/Sources/`（`CLIConfig.swift` / `MopeliumError.swift` / `Terminal.swift`）
- `Packages/MopeliumProviders/Sources/`（`ChatTypes.swift` / `OpenAICompatibleProvider.swift` / `SSEParser.swift` / `ToolCallingTypes.swift`）
- `Packages/MopeliumTools/Sources/`（Intatis 迁移工具面：file / patch / shell / git / document-media / browser）
- `Packages/MopeliumAgent/Sources/`（AI tool-calling agent loop 与 OpenAI-compatible tool-call stream provider）
- `Tests/`（`MopeliumCoreTests/ConfigTests.swift` / `MopeliumProvidersTests/SSEParserTests.swift` / `MopeliumToolsTests/MopeliumToolsTests.swift` / `MopeliumAgentTests/MopeliumAgentTests.swift`）
- `Package.swift`
- `project.yml`
- `Mopelium.xcodeproj/`
- `.gitignore`

## 禁止事项

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除用户未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。当前零第三方依赖（仅 Foundation + 条件 `FoundationNetworking`/`Darwin`）。
- 不把密钥、token、证书私钥、shared secret、账号密码、完整指纹、完整 API 响应、完整转写文本或个人隐私路径写入文档。
- 不绕过 `CLIConfigStore.writableField` 的 `api_key` 拒绝规则——API key 永远不存入配置文件，只从环境变量读取。
- 不把 OpenAI Chat Completions 请求/响应 JSON schema、SSE 事件格式、config.json schema 当作一次性内部细节随意改名。
- 不在 `OpenAICompatibleProvider` 中绕过 HTTP 状态校验（非 2xx 必须 `collectBodyPrefix` 并抛 `.httpStatus`）。
- 不移除 `OpenAICompatibleProvider.stream` 的 `onTermination` 取消处理（流式任务必须可取消）。

## 项目理解要求

修改前至少确认：

- 入口：`Apps/mopelium-cli/Sources/main.swift`（`@main struct MopeliumCLI`，`static func main() async`；命令 `ask`/`config show`/`config set`/`selftest`/`help`）。
- Mac 入口：`Apps/MopeliumMac/Sources/MopeliumMacApp.swift` → `MopeliumMacRootView`；主区域 `Chat`/`Tasks`/`Sources`/`Settings`。
- 配置解析链路：`CLIConfigStore.resolve(fileURL:environment:overrides:)` — 优先级 **CLI overrides > env（`MOPELIUM_BASE_URL`/`MOPELIUM_API_KEY_ENV`/`MOPELIUM_MODEL`/`MOPELIUM_STREAM`）> `~/.config/mopelium/config.json` > 默认**。默认：base `https://api.openai.com/v1`、env 名 `MOPELIUM_API_KEY`、model `gpt-4o-mini`、stream `true`。
- Chat 主链路：`main.swift` `runAsk` → `CLIConfigStore.resolve` → `config.requireAPIKey()` → `OpenAICompatibleProvider(baseURL:apiKey:)` → `ChatRequest(model, messages:[ChatMessage("user", prompt)], stream)` → stream 路径 `provider.stream`（`URLSession.shared.bytes` → 按行喂 `SSEParser.consume` → `emit` yield `ChatChunk`）或 complete 路径 `provider.complete`（`URLSession.shared.data` → 解码 `OpenAICompleteResponse`）→ `out(...)` 输出。
- AI 工具调用链路：CLI `ask --tools PATH` / Mac Chat `Tools` toggle → `OpenAICompatibleToolCallingProvider` → `MopeliumAgentLoop` → OpenAI-compatible `tools` request/stream tool_calls → `ToolRegistry.standard()` → `ToolContext(workspaceRoot:)` → tool observation 作为 `role=tool` 消息回灌模型；默认只允许 readOnly/network/exec，`run_shell`、write、destructive 需要显式开关。
- Mac Chat 主链路：`MopeliumChatViewModel.send` → `CLIConfigStore.resolve` → 普通聊天走 `OpenAICompatibleProvider` stream/complete；启用 Tools 后走 `OpenAICompatibleToolCallingProvider` + `MopeliumAgentLoop` → SwiftUI message bubble。
- Sources v0.4 链路：`MopeliumSourcesScreen.swift` 内 `MopeliumDocumentReader` 负责用户选择文件/文件夹后的文档浏览/读取；`MopeliumWebLookup` 负责 DuckDuckGo HTML 搜索与 HTTP(S) 页面抓取；`SourceToolConsoleCard` 通过 `ToolRegistry.standard()` 暴露从 Intatis 全量迁移的 53 个工具，包括 file / PDF / document-media / `web_fetch` / `browser_*` / shell / git / patch。
- API key 处理：从 `ProcessInfo.environment[apiKeyEnv]` 读取；`CLIConfigStore.writableField` 显式拒绝 `api_key`/`apiKey`/`api-key` 写入配置（抛 `.config("Refusing to store API keys...")`）；config 文件 `chmod 0600` + atomic 写。
- SSE 解析：`SSEParser`（行导向，buffer + dataLines）—— `:` 注释跳过、`data:` 累积、空行 dispatch、`[DONE]` 终止、多 `data:` 行用 `\n` join、CRLF 容忍。
- 错误模型：`MopeliumError`（config/provider/network/httpStatus/decoding/io/usage），`LocalizedError`；`mapError` 把 `URLError`→`.network`、`DecodingError`→`.decoding`。
- 终端 I/O：`out`→stdout、`errOut`→stderr、`truncated(_:limit:)`（默认 500，错误消息截断用）。

不确定的模块必须标注 `UNKNOWN` 或 `需要后续确认`，不要编造。

## 文档索引

- `docs/PROJECT_MAP.md`：目录、target、入口、关键文件和生成物地图。
- `docs/ARCHITECTURE.md`：总体架构、chat 主链路、配置解析、SSE 解析、数据模型和安全机制。
- `docs/CURRENT_STATE.md`：当前真实状态、已有能力、风险、工作区改动。
- `docs/TESTING.md`：环境、构建、测试、lint/format 与手动验证方式。
- `docs/DO_NOT_BREAK.md`：工程禁区、数据格式、协议、路径和回归要求。
- `docs/NEXT_TARGET.md`：临时下一目标记录；目标完成或不再有效后删除。

## 完成标准

完成任务前至少做到：

- 说明本轮实际阅读/检查过哪些源码、配置或测试。
- 只修改任务范围内文件。
- 保留用户已有改动。
- 运行与任务相称的检查；文档任务至少运行 `git diff --check` 与 `git status --short`。
- 将本轮已完成的持久性改动及时回写到相关项目文档；若无需更新文档，最终报告说明原因。
- 如未运行构建或测试，最终报告必须明确写"未运行构建/测试"。

## 最终报告格式

最终报告建议包含：

1. `MODEL_CHECK_RESULT`：当前模型名称；无法确认时写无法确认。
2. `PATH_CHECK_RESULT`：`pwd`、Git root、是否匹配预期。
3. `FILES_WRITTEN`：新增/修改文件。
4. `PROJECT_AUDIT_SUMMARY`：识别到的项目结构、主要模块和关键链路。
5. `DOCS_CONTENT_SUMMARY`：各文档内容摘要。
6. `VALIDATION_RESULT`：实际运行命令与结果。
7. `UNCERTAINTIES`：无法确认、需要人工确认的点。
8. `NEXT_RECOMMENDED_ACTION`：下一步建议；不要自动继续改业务源码。
