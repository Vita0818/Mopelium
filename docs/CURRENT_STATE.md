# CURRENT_STATE

最近一次自查日期：2026-06-25

## 当前真实状态总览

- Mopelium 是精简 macOS CLI 聊天客户端（OpenAI 兼容 Chat Completions），v0.1（单 commit）。
- Swift 包，3 product（Core lib / Providers lib / mopelium CLI），7 源文件，7 个单测，零外部依赖。
- 流式（SSE）与非流式 chat、config 解析（CLI/env/file/默认 4 级优先级）、API key 拒写入配置——均代码就绪并有部分测试。
- **无 README、无 LICENSE**。项目身份从代码推断。
- 真机 + 真实 key 的端到端验证状态 `UNKNOWN`（本轮未运行构建/测试）。

## 已有能力

| 能力 | 入口 / 关键类型 | 测试覆盖 | 手动验证 | 真机验证 |
|---|---|---|---|---|
| 流式 chat | `main.swift` `runAsk` / `OpenAICompatibleProvider.stream` | 无（HTTP 路径无测试） | UNKNOWN | UNKNOWN |
| 非流式 chat | `main.swift` `runAsk` / `OpenAICompatibleProvider.complete` | 无 | UNKNOWN | UNKNOWN |
| 配置解析（4 级优先级） | `CLIConfigStore.resolve` | ✅ 4 tests | UNKNOWN | UNKNOWN |
| 配置文件读写 | `CLIConfigStore.read/write` | ✅ `testSetWritesNonSecretConfig` | UNKNOWN | UNKNOWN |
| API key 拒写入 | `CLIConfigStore.writableField` | ✅ `testRejectsAPIKeyConfigField` | UNKNOWN | UNKNOWN |
| SSE 解析 | `SSEParser` | ✅ 3 tests | UNKNOWN | UNKNOWN |
| config show/set | `main.swift` | 间接（经 CLIConfigStore 测试） | UNKNOWN | UNKNOWN |
| selftest | `main.swift` `runSelfTest` | 无（非单测） | UNKNOWN | UNKNOWN |
| 错误处理 | `MopeliumError` / `mapError` | 间接 | UNKNOWN | UNKNOWN |
| 终端 I/O | `Terminal.out/errOut/truncated` | 间接 | UNKNOWN | UNKNOWN |

## 未完成 / 进行中

- **无 multi-turn 会话**：`runAsk` 仅单条 user message，无历史持久化。`UNKNOWN` — 是否计划加。
- **无 README/LICENSE**：项目身份未文档化。
- **HTTP 路径无自动化测试**：`OpenAICompatibleProvider` 的 stream/complete 无网络 mock，仅 `CLIConfig` 与 `SSEParser` 有单测。
- **HTTPS 未强制**：`CLIConfig.swift:125` 仅校验 `scheme != nil`，`http://` 端点会明文传 key。`UNKNOWN` — 是否应加固。
- **无请求超时配置**：依赖 `URLSession.shared` 默认。
- **非 Apple 平台 stream/complete 运行时抛错**：`#if canImport(Darwin)` 守卫，Linux/Windows 不可用 chat。

## 风险

- **零文档**：无 README，项目意图全靠代码推断，新接手者易误判。
- **HTTP 路径无测试**：核心 chat 功能回归全靠手动。
- **HTTPS 未强制**：用户配置 `http://` 端点会泄露 key。
- **API key 经 env**：出现在进程列表，泄露面不同于 Keychain。
- **单 commit v0.1**：无变更史，无 CHANGELOG，难追踪演进。

## 工作区状态

本轮自查（2026-06-25）为只读分析，未产生仓库改动。Git 状态应为 clean（单 commit `13a9ef6 v0.1`）。

## 文档与源码冲突

无现有 `docs/` 文档，故无文档-源码冲突。本目录文档为首次创建，均据源码推断。

值得注意的源码内设计点（非冲突，供后续参考）：

| 位置 | 内容 | 说明 |
|---|---|---|
| `CLIConfig.swift:125` | base URL 校验仅 `scheme != nil` | 不强制 https，`http://` 会明文传 key |
| `main.swift` `runAsk` | 仅发单条 user message | 无 multi-turn 会话支持 |
| `OpenAICompatibleProvider` | `#if canImport(Darwin)` 守卫 | 非 Apple 平台 chat 抛错 |
