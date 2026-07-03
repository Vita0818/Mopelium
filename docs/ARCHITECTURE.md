# ARCHITECTURE

最近自查日期：2026-06-25

## 总体架构

Mopelium 是精简 macOS CLI 聊天客户端，对接任意 OpenAI 兼容 Chat Completions 端点（`POST {base_url}/chat/completions`）。支持流式（SSE）与非流式响应，从 CLI flag / 环境变量 / JSON 配置文件解析配置，**拒绝**将 API key 持久化到配置文件。

```text
┌──────────────────────────────────────────────┐
│  mopelium CLI (main.swift @main)             │
│  命令: ask / config show / config set /      │
│        selftest / help                       │
└───────────┬──────────────────────────────────┘
            │ runAsk
            ▼
┌──────────────────────────────────────────────┐
│  CLIConfigStore.resolve (MopeliumCore)        │
│  优先级: CLI overrides > env > config.json >  │
│          默认                                 │
│  → ResolvedCLIConfig (baseURL, apiKey, model) │
└───────────┬──────────────────────────────────┘
            │ requireAPIKey() (从 environment[apiKeyEnv] 读)
            ▼
┌──────────────────────────────────────────────┐
│  OpenAICompatibleProvider (MopeliumProviders) │
│  stream: URLSession.shared.bytes → SSEParser  │
│          → ChatChunk yield                    │
│  complete: URLSession.shared.data → decode    │
│            OpenAICompleteResponse             │
└───────────┬──────────────────────────────────┘
            │ ChatChunk / ChatResponse
            ▼
┌──────────────────────────────────────────────┐
│  Terminal.out → stdout                        │
└──────────────────────────────────────────────┘
```

## 主要链路

### Chat 主链路（`mopelium ask "prompt"`）

```text
MopeliumCLI.main() (drop argv[0], strip leading --)
  -> run(args) -> runAsk(rest)
  -> flag 解析 (--no-stream/--model/--base-url/--api-key-env/--help)
     非 flag 参数 join 成 prompt
  -> CLIConfigStore.resolve(overrides:) 优先级合并
       CLI overrides > env(MOPELIUM_BASE_URL/MOPELIUM_API_KEY_ENV/MOPELIUM_MODEL/MOPELIUM_STREAM)
       > ~/.config/mopelium/config.json > 默认(base https://api.openai.com/v1, env MOPELIUM_API_KEY, model gpt-4o-mini, stream true)
  -> config.requireAPIKey() (environment[apiKeyEnv], 空则抛 .config)
  -> OpenAICompatibleProvider(baseURL:, apiKey:)
  -> ChatRequest(model:, messages:[ChatMessage("user", prompt)], stream:)
  -> stream 路径 (默认):
       provider.stream(request:) -> AsyncThrowingStream<ChatChunk>
         URLSession.shared.bytes(for:) -> HTTP 2xx 校验 (失败 collectBodyPrefix 抛 .httpStatus)
         bytes 按 0x0A 分行 -> SSEParser.consume(line) -> parser.flush() at EOF
         emit: .content -> yield ChatChunk; .done -> finish
       每个 chunk.content -> out(...) -> 末尾 out("\n")
     complete 路径 (--no-stream):
       provider.complete(request:) -> URLSession.shared.data(for:) -> 2xx 校验
       decode OpenAICompleteResponse -> choices.first?.message.content
       out(content) + 补末尾换行
  -> 错误冒泡到 main() -> errOut(localizedDescription) -> exit(1)
```

### 配置解析链路

```text
CLIConfigStore.resolve(fileURL:environment:overrides:)
  逐字段合并 (firstNonEmpty):
    base_url: overrides.baseURL | env.MOPELIUM_BASE_URL | config.baseURL | 默认
    api_key_env: overrides.apiKeyEnv | env.MOPELIUM_API_KEY_ENV | config.apiKeyEnv | 默认(MOPELIUM_API_KEY)
    model: overrides.model | env.MOPELIUM_MODEL | config.model | 默认
    stream: overrides.stream | parseBool(env.MOPELIUM_STREAM) | config.stream | 默认(true)
  base_url 校验: scheme != nil (注: 不强制 https)
  apiKey: environment[apiKeyEnv] (运行时读, 不入 ResolvedCLIConfig 持久字段)
  -> ResolvedCLIConfig(baseURL:, baseURLString:, apiKey:, apiKeyLoaded:)

CLIConfigStore.writableField(named:)
  接受: base_url/baseURL/base-url, model, api_key_env/apiKeyEnv/api-key-env
  拒绝: api_key/apiKey/api-key -> .config("Refusing to store API keys in config. Use `config set api_key_env ENV` instead.")

CLIConfigStore.write(_:to:)
  JSONEncoder (pretty, sortedKeys, withoutEscapingSlashes)
  atomic write + setAttributes([.posixPermissions: 0o600])
```

### SSE 解析链路

```text
SSEParser.consume(chunk: Data) -> [SSEParserEvent]
  append chunk -> buffer
  按 0x0A 分行:
    strip 尾部 \r
    空行 -> dispatchPendingEvent()
    ":" 开头 -> 注释跳过
    "data:" 开头 -> strip 可选前导空格 -> append dataLines
SSEParser.dispatchPendingEvent()
  dataLines join("\n")
  "[DONE]" -> [.done]
  else -> decode OpenAIStreamChunk {choices:[{delta:{content}}]}
          content 非空 -> [.content(content)]
          空/畸形 -> 静默跳过
SSEParser.flush() -> dispatchPendingEvent() (处理末尾未终止事件)
```

## 数据模型

| 类型 | 职责 | 持久化方式 | 关键字段约束 |
|---|---|---|---|
| `CLIConfig` | 配置模型 | `~/.config/mopelium/config.json`（JSON，`0600`，atomic） | snake_case keys: `base_url`/`api_key_env`/`model`/`stream`；默认 base `https://api.openai.com/v1`/env `MOPELIUM_API_KEY`/model `gpt-4o-mini`/stream `true` |
| `ResolvedCLIConfig` | 合并后配置 | 内存 | `apiKey` 运行时从 env 读，不入文件 |
| `ChatMessage` | 聊天消息 | 随请求 | `role: String`/`content: String` |
| `ChatRequest` | 请求 | 不持久化 | `model`/`messages`/`stream` |
| `ChatChunk` | 流式片段 | 内存 | `content: String` |
| `ChatResponse` | 完整响应 | 内存 | `content: String` |
| `MopeliumError` | 错误 | — | config/provider/network/httpStatus(Int,String?)/decoding/io/usage |

## 同步 / 通信机制

无多端、无多进程。单次 CLI 调用单回合：`runAsk` 仅发单条 user message，无会话/历史持久化（无 multi-turn）。`UNKNOWN` — 是否计划加会话。

## 安全机制

### API key 处理（设计上刻意 key-averse）
- **永不存入配置文件**：`CLIConfigStore.writableField` 显式拒绝 `api_key`/`apiKey`/`api-key`，抛 `.config("Refusing to store API keys...")`。已单测覆盖。
- 运行时从环境变量读：`ProcessInfo.environment[apiKeyEnv]`，env 名可经 `api_key_env` 配置（默认 `MOPELIUM_API_KEY`）。
- 无 Keychain 集成。

### 配置文件加固
- POSIX 权限 `0600`（仅 owner 读写）。
- 原子写（`.atomic`）。
- `.gitignore` 排除 `.env`/`*.env`/`secrets.json`。

### 传输
- Bearer token 经 `Authorization` header 发送。
- base URL 校验仅要求 scheme 非空，**不强制 https**——`http://` 端点会明文传 key。`UNKNOWN` — 是否应加固为强制 https。
- 错误响应截断 500 字符后暴露（`providerErrorMessage`）。

## 模式开关 / 内核切换

无。stream vs non-stream 由 `--no-stream` flag 或 `MOPELIUM_STREAM` env 或 config `stream` 字段控制。

## 与文档/源码的关系

- 无 README，所有架构结论从 7 个源文件 + `Package.swift` + `.gitignore` 推断。
- 流式与 `complete()` 用 `#if canImport(Darwin)` 守卫，非 Apple 平台抛 `.network("Streaming HTTP is unavailable on this platform.")`；有效支持平台为 macOS 13。
