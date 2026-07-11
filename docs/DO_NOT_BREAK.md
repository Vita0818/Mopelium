# DO_NOT_BREAK

最近自查日期：2026-07-08

## 工程禁区

- 不执行破坏性 Git 操作：`git reset --hard`、`git clean -fd`、`git checkout .`、强制 push、删除未提交文件。
- 未经用户明文要求具体 Git 操作，不 add、不 commit、不 push、不创建 PR。
- 不引入第三方 package，除非任务明确要求并同步更新文档/验证。
- 不回退用户已有改动；当前工作区已有 Mac app / Xcode project / docs 相关未提交改动。
- `Package.swift`、`project.yml`、`Mopelium.xcodeproj` 必须保持 target/dependency 一致；新增 SwiftPM target 后要同步 XcodeGen/Xcode 工程并验证 Xcode build。

## Provider / Config 不可破坏项

- `config.json` 路径仍为 `~/.config/mopelium/config.json`，snake_case keys：`base_url` / `api_key_env` / `model` / `stream`。
- `CLIConfigStore.writableField` 必须拒绝 `api_key` / `apiKey` / `api-key`。
- API key 永远只从环境变量读取，不写 config、docs、日志或 UI 持久化。
- Chat API 路径仍为 `POST {base_url}/chat/completions`。
- OpenAI-compatible tool-calling 路径也必须使用 `POST {base_url}/chat/completions`，请求体中的 `tools` / `tool_calls` / `tool_call_id` 字段名不得随意改名。
- HTTP 非 2xx 必须收集 body prefix 后抛 `.httpStatus`，不得当成功处理。
- `OpenAICompatibleProvider.stream` 的 `onTermination` 取消处理不得移除。
- `SSEParser` 必须保留 chunk 重组、CRLF 容忍、注释跳过、多 `data:` join、`[DONE]` 终止规则。

## Sources v0.4 不可破坏项

- 顶部本地文档读取必须由用户通过 `NSOpenPanel` 选择文件/文件夹触发；不得后台扫描任意用户目录。
- 必须拒绝读取 `.env`、`.env.*`、`secrets.json`、证书/key 文件，以及文件名包含 `private_key` / `api_key` / `access_token` / `password` 的路径。
- PDF 读取只能做文本抽取；不得假装 OCR 已实现。
- Web URL 必须校验为 `http` 或 `https` 且有 host。
- 顶部 Web Lookup 不得读取或复用浏览器 cookies、localStorage、profile 数据或账号登录态。
- Web 搜索/抓取输出必须 bounded：当前 response bytes 3MB、正文 60k chars。
- 不要把抓取到的完整网页或完整文档自动写入仓库文档。
- Full Intatis Tool Surface 运行工具前必须有用户选择的 workspace；工具路径必须通过 `PathConfinement` 限定在 workspace 内。
- Browser profile/state/history/downloads 只能写入所选 workspace 的 `.mopelium/browser/`；不得写入 `~/.config`、Keychain 或浏览器真实用户 profile。
- `browser_profiles`、`browser_history`、`browser_downloads` 只能输出 metadata；不得读取或输出 cookies、localStorage、profile DB、runtime marker 内容、下载文件内容或密码/token。
- `browser_profile_delete` 必须保留 `confirmProfile` 精确匹配保护。
- `browser_screenshot` 和 `browser_download` 的 changedFiles 必须限定在 workspace 内；`browser_upload_file` 只能引用 workspace 内文件。
- `browser_type` 必须遮蔽 observation 中的输入值，并拒绝疑似 password / 2FA / token / API key 输入目标。
- destructive/write/exec/network 工具的 `ToolDescriptor.sideEffect` 不得随意降级。
- AI agent loop 不得绕过 `MopeliumAgentToolPolicy`：默认不允许 `run_shell`、write、destructive；工具路径必须继续通过 `ToolContext(workspaceRoot:)` 与 `PathConfinement` 限定。

## UI 不可破坏项

- `MopeliumMacRootView` 的四个 section：`Chat` / `Tasks` / `Sources` / `Settings` 必须可路由。
- `Chat` 仍应使用真实 `CLIConfigStore` 和 `OpenAICompatibleProvider`，不能退回 mock。
- `Chat` 的 Tools 模式必须要求用户选择 workspace；不得无 workspace 或后台扫描用户目录后自动给 AI 工具权限。
- `Sources` 页面应保持 document reader 与 web lookup 两块真实可操作区域。
- `Sources` 页面应保持 full tool console 可操作，至少能选择 workspace、选择工具、编辑 JSON 参数、运行工具并显示 observation/changedFiles。
- `Settings` 不得显示真实 API key，只显示 env 名和 loaded/missing 状态。

## 验证要求

代码任务至少运行：

```sh
swift build
swift test
swift run mopelium selftest
xcodebuild -project Mopelium.xcodeproj -scheme MopeliumMac -configuration Debug -derivedDataPath .build/XcodeDerivedData build
```

在 Codex 沙盒内如 SwiftPM 不能写用户 cache，可使用：

```sh
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift build --disable-sandbox
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift test --disable-sandbox
CLANG_MODULE_CACHE_PATH=/Users/vita/Vitemis/Virgo/Mopelium/.build/module-cache swift run --disable-sandbox mopelium selftest
```

文档任务至少运行 `git diff --check` 与 `git status --short`。

真实浏览器 smoke、真实联网 Web 搜索/网页抓取、PDF 文本抽取、NSOpenPanel 文件选择、真实上传/下载/登录态目前仍需要人工或脱离 sandbox 验证。

若 `swift test` runner 在 Codex sandbox 内构建后卡住，不得标记为通过；至少运行 `swift build --build-tests`、增强后的 `swift run mopelium selftest` 和 Xcode build，并在最终报告中明确说明完整 XCTest 未完成。
