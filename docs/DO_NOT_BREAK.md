# DO_NOT_BREAK

本文列出不可破坏的工程禁区、数据格式、协议、路径和回归要求。修改前必须确认不违反下列任一条目。

## 工程禁区

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR；编辑、整理、修复、验证或准备工作都不等于提交请求。
- 若用户要求提交，只提交当前 Git root 中与本任务相关的文件；不得递归进入、暂存、提交或推送子仓库、submodule、nested Git repo 或依赖 checkout。
- 不引入新依赖，不改构建脚本，不改测试源码，除非任务明确要求。当前零第三方依赖。
- 不绕过 `CLIConfigStore.writableField` 的 `api_key` 拒绝规则。

## 数据格式禁区

- **config.json**：`~/.config/mopelium/config.json`。JSON，snake_case keys：`base_url`/`api_key_env`/`model`/`stream`。pretty-printed + sorted keys + 不转义 `/` + atomic 写 + `chmod 0600`。**永不包含 `api_key`**（`writableField` 显式拒绝）。
  ```json
  {"api_key_env":"MOPELIUM_API_KEY","base_url":"https://api.openai.com/v1","model":"gpt-4o-mini","stream":true}
  ```
- **config show 输出**（`ConfigShow`，snake_case）：`base_url`/`api_key_env`/`api_key_loaded`/`model`/`stream`。
- **Chat API 请求体**（`OpenAIChatRequestBody`）：`POST {base_url}/chat/completions`，`{model, messages:[{role,content}], stream}`。
- **非流式响应**（`OpenAICompleteResponse`）：`{choices:[{message:{content}}]}`。
- **流式 SSE**（`OpenAIStreamChunk`）：行导向，`data: {choices:[{delta:{content}}]}`，`[DONE]` 终止。事件以空行分隔；CRLF 容忍；`:` 注释跳过；多 `data:` 行用 `\n` join。

> 这些格式承载与 OpenAI 兼容端点的线协议契约，改字段名/结构会导致端点不识别或解析失败。

## 协议禁区

- **HTTP 请求**：`baseURL.appendingPathComponent("chat/completions")`，POST。header：`Content-Type: application/json`、`Accept: text/event-stream`（stream）或 `application/json`（非 stream）、`Authorization: Bearer {apiKey}`。不得改路径拼接方式或移除 header。
- **HTTP 状态校验**：非 2xx 必须 `collectBodyPrefix`（最多 4096 字节）并抛 `.httpStatus(Int, String?)`；不得放行非 2xx。
- **错误消息**：`providerErrorMessage` 尝试 `{error:{message}}` → `{message}` → 原始 UTF-8 文本，截断 500。不得泄露完整响应。
- **SSE 解析规则**：`SSEParser` 必须容忍任意 chunk 切分（buffer 重组）；`[DONE]` 必须 finish；空/畸形 `data:` 静默跳过（不得抛错中断流）。

## 路径禁区

- **config 文件**：`~/.config/mopelium/config.json`（`CLIConfigStore.defaultURL()`）。权限 `0600`，atomic 写。
- **temp**：`FileManager.default.temporaryDirectory`（测试用随机子目录）。

## 回归要求

- `CLIConfigStore.writableField` 拒绝 `api_key`/`apiKey`/`api-key` 三种大小写/分隔写法，抛含 "Refusing to store API keys" 的 `.config` 错误。已有单测 `testRejectsAPIKeyConfigField` 覆盖。
- `CLIConfigStore.resolve` 优先级**必须**为 CLI overrides > env > file > 默认。已有单测 `testEnvironmentOverridesFileConfig` 覆盖 env > file。
- `CLIConfigStore.write` 必须 atomic + `0600`。
- `SSEParser.consume` 必须能在任意 chunk 切分下重组（5 字节切分测试 `testReassemblesAcrossArbitraryChunks`）。
- `SSEParser` 必须忽略 `:` 注释与空 delta（`testIgnoresCommentsAndEmptyDeltas`）。
- `OpenAICompatibleProvider.stream` 的 `onTermination` 必须取消 Task（流式可取消）。
- `OpenAICompatibleProvider` 非 Darwin 平台 stream/complete 必须 throw（`#if canImport(Darwin)` 守卫）。
- `main.swift` 未知 `--*` flag 必须 throw usage（不得静默忽略）。

## 不可降级项

- API key 永不入配置文件：`writableField` 拒绝规则不得移除或放宽。
- config 文件 `0600` 权限不得降级（如改 `0644`）。
- HTTP 非 2xx 必须抛错，不得当作成功。
- SSE `[DONE]` 必须终止流，不得继续 yield。
- `truncated(_:limit:)` 默认 500 不得在错误消息路径移除（防泄露完整响应）。
- `mapError`：`MopeliumError` 透传，`URLError`→`.network`，`DecodingError`→`.decoding`——映射不得丢失类型信息。

## 验证要求

修改后必须运行哪些验证才能视为安全：

```sh
swift build
swift test                              # 全部 7 个测试
swift test --filter MopeliumCoreTests   # 仅配置测试
swift test --filter MopeliumProvidersTests  # 仅 SSE 测试
swift run mopelium selftest             # 内置 smoke test（非单测）
```

- 文档任务：至少 `git diff --check` + `git status --short`
- 未运行构建/测试时，最终报告必须声明"未运行构建/测试"
- `OpenAICompatibleProvider` 的 HTTP 路径无自动化测试（无网络 mock），改动须手动验证：
  ```sh
  MOPELIUM_API_KEY=sk-... swift run mopelium ask "你好"
  MOPELIUM_API_KEY=sk-... swift run mopelium ask --no-stream "你好"
  ```
