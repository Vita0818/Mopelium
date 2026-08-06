# Mopelium

一个 Apple-first、Swift-native 优先的本地 AI 工作台：**Chat + Cowork + Code** 三合一，底层共享
headless Agent Kernel。当前工程架构见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)，根
[`ARCHITECTURE.md`](ARCHITECTURE.md) 保留早期设计稿；项目来源与许可证状态见
[`NOTICE.md`](NOTICE.md)，开源复用规则见 [`docs/OPEN_SOURCE_REUSE.md`](docs/OPEN_SOURCE_REUSE.md)。

活动源码已采用固定 v0.26 参考快照的功能与界面基线，并全部改为 Mopelium 产品标识；这表示
源码基线版本，不等于 App marketing version（`project.yml` 当前仍为 `0.12`）。真实 API key
只从环境变量读取，配置和设置只保存变量名。

## 功能状态

### Implemented

- OpenAI-compatible 流式聊天，事件日志驱动 projection。
- 单 workspace Code agent：文件读写、搜索、patch、结构化 Git，以及受 WorkspaceLease 管理的持久终端。
- 确定性权限闸：敏感路径 / workspace escape / sandbox shell / 危险 shell 命令硬拒绝，写入和大多数 shell 默认问用户。
- Cowork：稳定 `@main`、多 Agent registry、durable Goal/WorkTask、委派/回报、受控 message bus 与自动权限审查。
- macOS 完整 Chat/Code/Cowork 界面、recent sessions、恢复与 inspector；iOS 为编译期隔离的 Chat 子集。
- Artifact store：文件附件、图片产物、转写文本、视频任务产物的存储抽象。
- iOS 真子集 target：只链接 Chat / Provider / Conversation / Artifact / Multimodal / SharedUI 子集。
- CLI：`chat` / `code` / `cowork` REPL、slash commands、附件输入、离线 selftest。

### Partial

- Multimodal：图片生成和批量转写有 OpenAI-compatible provider；视频只有 submit/poll 抽象和测试 fake provider。
- App Store 级 git backend：当前 git 仍是 `ProcessGitService` spawn `git`，App Store 沙盒内需要进程内 git backend。
- 真实 provider、真机、第三方浏览器登录、长时间资源与强杀恢复矩阵仍需外部验证。

### Planned

- 实时流式语音输入 / ASR session。
- 完整视频 provider 配置与 GUI 入口。
- 进程外 kernel transport（stdio / daemon）。
- replacement-history compaction checkpoint 与同一 submission 原位 resume。

---

## v0.1 包含什么

以下 v0.1–v0.5 小节是历史里程碑说明；当前实现和安全合同以上方功能状态及
[`docs/CURRENT_STATE.md`](docs/CURRENT_STATE.md) 为准。

一个流式聊天 app，但从第一天起数据路径就是
`Composer → Command → Kernel（进程内）→ Provider → Event Log → projection → UI`，
**而不是**让视图直接调 API。正是这条纪律让 v0.2（Code）与 v0.3（Cowork）成为增量叠加而非重写
（ARCHITECTURE.md §7.1）。

已包含：

- OpenAI-compatible 流式聊天（SSE），且多端点 / 多 wire 的接缝已经就位
  （`WireFormat`、`ProviderEndpoint`、`ModelRef`）。
- append-only 的每会话事件日志（JSONL）作为唯一真相源，支持 replay + resume。
- 三栏 SwiftUI 外壳（sidebar / thread / inspector）。
- API key 仅在请求时从环境变量读取；配置只保存环境变量名。
- Artifact store 骨架（附件 / 转写）。

**v0.1 暂未包含**：多 Agent（v0.3）、多模态（v0.4）、iOS（v0.5）。

---

## v0.2 包含什么（Code）

单 workspace 的 coding agent：模型可调工具读写本地文件，每个工具调用先过确定性权限闸。

已包含：

- 工具：`read_file` / `list_files` / `search_text` / `write_file` / `apply_patch`（unified diff applier）/ `run_shell` / `git_status` / `git_diff`，每个都过**路径围栏**（`..`、越界、symlink 逃逸一律拒绝）。
- OpenAI function-calling：流式 `tool_calls` 按 index 累积装配。
- 确定性权限闸（A 层）：密钥 / `.env` / 越界 / `sudo` 等硬 `deny`；普通写 / patch / shell 默认回到用户确认；只有极窄的 confined read-only shell argv 会自动放行。
- 单 Agent 工具循环：`流式 → tool_call → 权限 → 执行 → observation → 续`，带迭代上限。
- Code 三栏界面：tool-call 卡、permission 卡（`apply_patch` 内联显示 diff，Approve/Reject 即 accept/reject）、patch / terminal 输出；workspace 选择（security-scoped）。

> **git 注意**：v0.2 的 `ProcessGitService` 通过 spawn `git` 实现，适用于 Developer-ID / `swift run` 开发。App Store 沙盒构建需换成进程内 libgit2 后端（已在 `GitService` 协议后留好接缝）。

---

## v0.3 包含什么（Cowork）

同一个 thread 里激活多个 Agent，每个绑定不同 workspace，Agent 之间只能经受控的 message bus 通信。

已包含：

- **多 Agent 编排**（`Orchestrator`）：`@AgentName` 把消息定向给某个 Agent，多 Agent 输出合并进同一 thread（按 agent 名区分）。
- **受控 Agent 间通信**：唯一通道是 `ask_agent` 工具 → per-agent `AgentMessenger` → `MessageBus` → `Mediator`。Agent **不能**直接读彼此目录。
- **Mediator 转发规则**：`SecretScanner` 命中（密钥/token/private key）硬 `block`；超长原文 `block`（强制摘要）；可选 `ForwardingReviewer` 做"摘要 vs 大段源码"判断。每次转发都记 `agent_to_agent_message` + `permission_review`。
- `ModelPermissionReviewer` 类型保留在代码中并有测试，但默认权限链路暂未接入自动 reviewer；本阶段不会让模型自动批准权限请求。
- **Cowork 界面**：左栏 agent 名册 + Add Agent，中栏合并 thread（含 `↔` agent-to-agent 卡），右栏 per-agent 详情；`@mention` composer。

---

## v0.4 包含什么（Multimodal）

生图 / 转写 / 视频任务抽象，产物进 Artifact Store，并以 `artifact_added` / `artifact_progress` 事件出现在 thread 与右栏。

已包含：

- **Provider 能力扩展**：`ImageGenerationProvider`（OpenAI `/images/generations`，b64）、`TranscriptionProvider`（OpenAI `/audio/transcriptions`，multipart）、`VideoGenerationProvider`（submit/poll 抽象，无标准 wire，注入式）。
- **`MultimodalService`**（actor）：调 provider → 写 `ArtifactStore` → 发事件；视频任务轮询发 `artifact_progress`，完成发 `artifact_added`。
- **Chat 集成**：composer 的 🖼 按钮用当前输入当 prompt 生图；右栏 artifact 面板显示图片预览 / transcript 文本。
- 默认 `dall-e-3` / `whisper-1` 走同一 OpenAI 端点（可在 `AppConfig` 改）。

> **注意**：v0.4 是批量转写（音频 → 文本）；实时流式 ASR（websocket）与音频采集 UI 留作后续。视频无默认 OpenAI-compatible 端点，需注入具体 provider。

---

## v0.5 包含什么（iOS 子集）

`iOS ⊂ macOS` 的真子集：iOS app **只链接** Core / Protocol / Providers / Conversation / Artifacts / Multimodal / SharedUI。

- **结构性保证**：`MopeliumiOS` 的依赖闭包**不含** Tools / Permission / AgentKernel / Cowork —— 不是运行时关开关，而是这些包根本没被链接，没有任何通往本地 workspace 的代码路径（ARCHITECTURE.md §4.1）。校验脚本确认其传递闭包里没有 workspace stack。
- **保留**：流式聊天、OpenAI-compatible、artifact store（图片/转写/视频任务产物）、基础会话日志、环境变量凭据解析、右栏 artifact 面板。
- **删除**：本地 workspace agent、shell / git / diff / patch、多本地 Agent。
- **复用**：`ChatViewModel` + `ThreeColumnShell` 原样复用；`PlatformProfile.current = .iOS` 让侧栏只剩 Chat；图片预览在 iOS 走 UIKit 分支。
- iOS 文件访问止于附件，不会升级为 workspace —— 因为升级逻辑就在 iOS 不链接的那些包里。

> 真正的 iOS app 用 Xcode iOS App target 链接这些子集包；仓库里的 `MopeliumiOS` executableTarget 承担源码 + 依赖声明 + 编译核对。语音采集 UI（AVAudioRecorder）留作后续。

---

## 目录结构

| 路径 | 模块 | 职责 |
|------|--------|------|
| `Packages/MopeliumCore` | MopeliumCore | ID、`SessionKind`、`SideEffect`、`PlatformProfile`、错误类型 |
| `Packages/MopeliumProtocol` | MopeliumProtocol | `Envelope`、`Event`、`Command`、JSON-RPC 词汇 |
| `Packages/MopeliumProviders` | MopeliumProviders | capability provider + OpenAI wire/SSE/tool-calling/图像/转写 + registry |
| `Packages/MopeliumArtifacts` | MopeliumArtifacts | artifact store |
| `Packages/MopeliumConversation` | MopeliumConversation | 事件日志、projection、**无工具的 `ChatLoop`**、`CodeProjection` |
| `Packages/MopeliumTools` | MopeliumTools | 路径围栏 + 文件 / git / shell 工具（哑执行器）|
| `Packages/MopeliumPermission` | MopeliumPermission | 确定性权限闸 + SecretScanner + profiles + 模型审查员（B 层）|
| `Packages/MopeliumAgentKernel` | MopeliumAgentKernel | Agent + ContextBuilder + 工具循环 |
| `Packages/MopeliumCowork` | MopeliumCowork | AgentRegistry + Mediator + MessageBus + Orchestrator + `ask_agent` |
| `Packages/MopeliumMultimodal` | MopeliumMultimodal | 生图 / 转写 / 生视频任务 → artifacts + 进度事件 |
| `Packages/MopeliumSharedUI` | MopeliumSharedUI | SwiftUI 三栏外壳 + `ChatViewModel` + Code 视图 |
| `Apps/MopeliumMac` | MopeliumMac | macOS app：接线、环境变量凭据解析、entitlements、Code/Cowork 接线 |
| `Apps/MopeliumiOS` | MopeliumiOS | iOS app：chat 子集（不链接 workspace stack）|

单一根 `Package.swift`；模块 == target；target 依赖强制 ARCHITECTURE.md §2.1 的无环依赖图。

本仓库当前以 SwiftPM 5.9 manifest、Swift 5.9 language mode 和 XcodeGen 组织；GUI target
要求 macOS 26 / iOS 26 SDK。首次构建会解析 vendored renderer 锁定的 exact SwiftPM 依赖。

---

## 构建、测试、运行（macOS 26+）

### 库 / 逻辑层（不需要 Xcode）

```bash
swift build       # 编译 11 个库
swift test        # 运行全部 XCTest 套件——无需联网
```

### 跑起 App（生成 Xcode 工程）

仓库是 **Swift Package（纯库）**，不含 `.xcodeproj`。**App 是 Xcode 的 App target**，链接这些库——
SwiftPM 产不出 `.app`，iOS app 更是只能由 Xcode 构建。这就是"在 Xcode 里 build 这个 Package
不出 app"的原因。用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 一条命令生成工程：

```bash
brew install xcodegen     # 一次性
make app                  # = xcodegen generate && open Mopelium.xcodeproj
```

然后在 Xcode 里选 **MopeliumMac** 或 **MopeliumiOS** scheme，按 Run。`project.yml` 定义了这两个
App target（mac 链全部 11 个库；iOS 只链 chat 子集 7 个），并接上各自的 `Info.plist` / entitlements。

- 真机 / 归档需在 target 的 Signing 里选你的 Team（本地 mac 运行与 iOS 模拟器通常自动签名即可）。
- 启动前在运行环境设置 `MOPELIUM_API_KEY`，或用 `MOPELIUM_API_KEY_ENV` 指定另一个变量名；设置页只编辑环境变量名，不接收或持久化 key。默认端点是
  `https://api.openai.com/v1`，默认模型在 `Apps/MopeliumMac/Sources/AppConfig.swift`
  （iOS 在 `IOSConfig.swift`）中定义。
- macOS 工程默认使用 **Developer-ID entitlements** 和 `.macDeveloperID` profile，以提供完整 Code/Cowork
  能力。未来 chat-only App Store 构建可按 `project.yml` 注释切换到 sandbox entitlements 和
  `.macAppStore`。

> 不想装 XcodeGen 也行：Xcode 里 File ▸ New ▸ Target ▸ App 建 macOS/iOS App target，把本仓库
> 作为 local Swift package 依赖，按上面的库清单勾选 product 即可。

---

## CLI（`mopelium`）

CLI 是真正的 SwiftPM 可执行文件，**不需要 Xcode**：

```bash
swift run mopelium settings        # 交互式设置页：endpoint / API key 环境变量名 / 模型 / 推理 / 默认模式
swift run mopelium                 # 跑默认模式（设置里选的，默认 chat）
swift run mopelium chat            # 流式对话（无工具）
swift run mopelium code .          # coding agent（读/写/patch/shell/git，写入走终端审批）
swift run mopelium cowork .        # 多 Agent：/agent add <name> <path>，再 @name 发消息
swift run mopelium selftest        # 零配置自检：离线跑通 chat + code 写/读文件（无需 key）
swift run mopelium config          # 打印当前解析到的配置
```

**首次使用**：先把真实 key 放进 `MOPELIUM_API_KEY`（或 `MOPELIUM_API_KEY_ENV` 所指向的变量），
再运行 `swift run mopelium settings` 设置 endpoint、非秘密的 API-key 环境变量名、默认模型 /
推理强度 / 默认模式。`~/.config/mopelium/config.json` 永远不保存真实 key。

**会话内 slash 命令**：`/model <name>` 换模型、`/reasoning <level|off>` 调推理、
`/verbose [on|off]` 展开/折叠工具输出、`/mode <chat|code|cowork>` 实时切模式、`/clear` 新会话、
`/config` 看当前、`/help`、`/exit`。

**键盘 / 快捷键**：CLI 用自带的 raw-mode 行编辑器（不再走 `readLine` 的 canonical 模式），所以
**中文整字退格**、←/→ 移光标、Home/End 跳行首尾、↑/↓ 翻历史、Ctrl-U/K/W 删除都正常（之前按一次退格
只删半个汉字、方向键冒 `^[[C`，正是 canonical 模式所致）。Ctrl 快捷键：**Ctrl-A** 切模式、**Ctrl-L**
换模型、**Ctrl-S** 打开设置、**Ctrl-C** 退出。非交互（管道 / `selftest`）自动回退普通 `readLine`。

**折叠输出**：工具调用与终端输出默认折叠成单行摘要（`⎿ 首行… (+N 行)`），`/verbose on` 一键展开、`off`
收起。**等待模型**时底部转 `⠋ Thinking… 650ms` 计时，首个 token 到达即清除。

**每轮统计**：每条回复结束打印一行 `⎿ 1.8s · ttft 0.32s · 1843 tok (1623 in / 220 out)`——
总耗时、首字耗时、token（`in` 即上下文占用）。token 需端点支持 `stream_options.include_usage`
（OpenAI 及多数兼容端点支持）；个别端点若因此报错，设 `MOPELIUM_USAGE=0` 关掉。

**视觉输入（看图）**：`/attach <图片路径>` 把图片排队（本地图自动转 base64 data URL），下一条消息
带给模型；非图片的 UTF-8 文本文件会作为上下文内联。**chat 和 code 都支持**（cowork 暂未接）。消息
`content` 会按 OpenAI vision 格式编码成 `[{text}, {image_url}]`。配合多模态模型用，例如
`MOPELIUM_MODEL=qwen-vl-max`。注意这是「看图」（视觉输入），与之前的「生图」（输出）是两回事。

**Cowork（多 Agent，带协调者）**：`mopelium cowork` 进入后，自动有一个协调者 `@main`（绑当前目录）。
**直接描述任务就行** —— `@main` 能自己用 `spawn_agent` / `ask_agent` / `list_agents` / `remove_agent`
新建、委派、卸载子 agent（即业界常见的 *supervisor / orchestrator-worker* 模式），不必手动 `/agent add`：

```text
cowork ❯ 读一下当前项目，再开一个 reviewer 复核我的改动
         # @main 自己 spawn 出子 agent，用 ask_agent 委派、汇总，必要时 remove_agent
cowork ❯ /agents                                  # 看名册（含 @main 自己 spawn 的）
cowork ❯ @reviewer 重点看并发安全                   # 也可手动定向给某个 agent
```

仍可手动接管：`/agent add <name> <path> [model]` 加 agent、`/agent remove <name>` 卸载、`/attach`
把图带给目标 agent；不带 `@` 默认发给 `@main`（`@main` 受保护，不会被 `remove_agent` 删）。每个 Agent
绑不同 workspace、可各用不同模型。Agent 之间**只能**经受控 message bus 通信（输出里 `↔ A→B` +
`permission_review` 审计；密钥/超长内容会被 Mediator 拦），每段回复前有 `● 名字` 标明谁在说。等待模型
时底部显示 `⠋ Thinking… 650ms` 计时，首个 token 到达即清除。统计/推理强度对每个 agent 同样生效。

想先零配置确认链路：`swift run mopelium selftest` —— 内置 fake 模型，离线把 **chat 完整一轮** +
**code 写文件再读回**走一遍，复用的就是真正的 ChatLoop / AgentLoop / 渲染 / 审批代码。

`mopelium code` 跑的就是完整 Agent：模型可调用文件/搜索/patch、结构化 Git，以及
`exec_command` / `write_stdin` 受控终端工具；写入、命令与远程操作继续经过权限审查。

**装成系统命令**（像 `curl` / `chmod` 那样从任何目录用 `mopelium` 唤醒）：

```bash
make release            # 编译 release 版到 .build/release/mopelium
sudo make install       # 软链到 /usr/local/bin/mopelium（在默认 PATH 上）
# 没 sudo 也行：make install BINDIR=$HOME/.local/bin（再把该目录加进 PATH）
which mopelium && mopelium help
```

软链一次即可：之后每次 `make release` 都即时生效，无需重装。然后 `cd` 进任意真实项目目录，
直接 `mopelium code` / `mopelium cowork` / `mopelium chat`（workspace 默认就是当前目录，不用写 `.`）。
端点、模型和 API-key 环境变量名从 `~/.config/mopelium/config.json` 读；真实 key 始终来自进程环境，
与所在目录无关。卸载：`sudo make uninstall`。

## 接任何家的 API（不只是 OpenAI）

"支持 OpenAI" 指的是 **OpenAI-compatible 协议**，不是只连 openai.com。换个 `MOPELIUM_BASE_URL`
就能接任意一家：

```bash
# Ollama（本地，key 随便填）
MOPELIUM_BASE_URL=http://localhost:11434/v1 MOPELIUM_API_KEY=ollama MOPELIUM_MODEL=llama3.1 \
  swift run mopelium chat
# OpenRouter
MOPELIUM_BASE_URL=https://openrouter.ai/api/v1 MOPELIUM_API_KEY=sk-or-... \
  MOPELIUM_MODEL=anthropic/claude-3.5-sonnet swift run mopelium chat
# DeepSeek
MOPELIUM_BASE_URL=https://api.deepseek.com/v1 MOPELIUM_API_KEY=sk-... \
  MOPELIUM_MODEL=deepseek-chat swift run mopelium code .
```

**切模型**：改 `MOPELIUM_MODEL`。**切厂商**：改 `MOPELIUM_BASE_URL`（+ 对应 key / model）。
**调思考/推理强度**：`MOPELIUM_REASONING=minimal|low|medium|high` —— 只在设置时才下发
`reasoning_effort`，普通模型或不支持的端点不受影响：

```bash
MOPELIUM_API_KEY=sk-... MOPELIUM_MODEL=o4-mini MOPELIUM_REASONING=high swift run mopelium chat
```

**调单轮工具步数上限**：长任务（多次读写/委派）默认每轮最多 50 个工具往返，到顶才报
`max_iterations`。嫌不够就调大：`MOPELIUM_MAX_STEPS=200`（chat / code / cowork 都生效）。

`swift run mopelium config` 随时看当前解析到的端点 / 模型 / 推理强度。

架构本就端点无关：`ProviderEndpoint.baseURL` 可配，`WireFormat` 是枚举（目前 `.openai`，留了
加 `.anthropic` / `.gemini` 的缝）。GUI 设置提供 Base URL / Model / API-key 环境变量名；
它不会显示、接收或保存真实 key。

---

## 分发：两个构建，同一 capability 边界

本地 workspace、进程与终端能力只进入 Developer-ID workbench；App Store 形态保持 chat-only：

| 构建 | `AppConfig.platformProfile` | Entitlements | Managed terminal |
|-------|------------------------------|--------------|:---:|
| Mac App Store（沙盒、预留） | `.macAppStore` | `MopeliumMac.AppStore.entitlements` | ✗ |
| Developer-ID workbench | `.macDeveloperID` | `MopeliumMac.DeveloperID.entitlements` | ✓ |

Git 工具目前使用受控 `ProcessGitService`（Developer-ID 开发形态）；若未来要在 App Store
沙盒内开放 Git，需要先替换为进程内 backend。`.macAppStore` 不注册本地终端能力。

---

## 测试覆盖

v0.1：

- **Core** —— profile 预设、ID 裸字符串编码、ID 生成。
- **Protocol** —— 每种事件类型的 `Envelope` round-trip；扁平 wire 形状；`Command`
  round-trip + method 字符串。
- **Providers** —— SSE 跨任意 chunk 边界重组；OpenAI 流式 → delta + done；registry
  解析 + 未知端点报错。
- **Artifacts** —— 添加 / 读取 / 重载后持久化；缺失 artifact 报错。
- **Conversation** —— append/replay/resume 的 seq 连续性；`replay(from:)`；stream
  先回放再实时；`ChatLoop` 流式 + projection；跨轮次历史。

v0.2：

- **Protocol（v0.2）** —— 新增 6 个事件 + 2 个命令 round-trip；`JSONValue` round-trip。
- **Providers（tool-calling）** —— 流式 `tool_calls` 跨 fragment 装配；纯文本流；消息 JSON 形状。
- **Tools** —— 路径围栏（越界 / 绝对 / `..` 折叠）；unified diff 解析 + 应用 + 不匹配拒绝；
  porcelain 解析；文件读写列搜；`apply_patch` 改文件；shell / git 注入 fake。
- **Permission** —— SecretScanner / ShellInspector；gate 各分支（读 allow、写 reviewed→pass、
  manual→ask、`.env`/越界/沙盒 shell/`sudo` deny、`ls` allow、locked deny）；engine 降级与
  reviewer 路由。
- **AgentKernel** —— 批准写执行并产事件；拒绝写不执行；只读工具免确认。
- **Conversation（Code）** —— `CodeProjection` 折叠 tool/result/patch/agent 事件。

v0.3：

- **Protocol（v0.3）** —— 5 个 Cowork 事件 round-trip；`agent_to_agent_message` wire type；`profile.set` 命令。
- **Permission（reviewer 类型）** —— 解析 allow / deny（含前后包裹文本）/ 不可解析回退 ask；engine 对 hard `deny` 的测试覆盖存在。默认产品链路暂未接入自动 reviewer。
- **Cowork** —— Mediator 正常转发 / 密钥 block / 超长 block / reviewer block；MessageBus 转发记两条日志、block 返回 nil 并记 `deny`；Orchestrator 端到端 agent-to-agent 经双向 mediation 并记录；含密钥的问题在到达对端前被拦截。

v0.4：

- **Protocol（v0.4）** —— `artifact_added` / `artifact_progress` round-trip + wire type。
- **Providers（多模态）** —— image gen 解析 b64 / HTTP 错误抛错；transcription 解析 text；registry 解析 image provider / 无配置返回 nil。
- **Multimodal** —— `generateImage` 写 artifact 并发事件；`transcribe` 写 transcript；`generateVideo` 轮询发 `progress` 后 `artifact_added`。
