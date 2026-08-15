# AI_PROVIDER_MODEL_CONFIGURATION

文档状态：当前 AI 配置操作合同
最后核对：2026-08-14
产品代码基线：Intatis v0.48（build 48；来源 commit 标题 v0.54）

## 1. 适用范围

本文面向维护 Mopelium 的 AI coding / operations agent。Mopelium 是显示品牌；provider、model、
variant、catalog、agent binding、CLI 和配置发现继续使用当前 Intatis 后端身份。

处理以下事项前必须先读本文：

- 新增或修改 provider route、model、options 或 variant；
- 修改 API-key reference；
- 配置 Cowork 不同 agent 的 exact profile；
- 排查配置刷新、现有 agent binding 或 CLI/macOS 解析差异。

本文不授权 AI 获取、查看、迁移或输出真实 API key，也不授权把 `INTATIS_*`、`intatis.json`、
Intatis 类型或 durable identity 重命名为 Mopelium。产品品牌边界见
`MOPELIUM_PRODUCT_DIRECTION.md`。

## 2. 内部身份保持 Intatis

当前规范名称为：

- 配置文件：`intatis.json` / `intatis.jsonc`；
- 配置选择：`INTATIS_CONFIG`；
- CLI override：`INTATIS_MODEL`、`INTATIS_BASE_URL`、`INTATIS_API_KEY`、
  `INTATIS_REASONING`；
- CLI：`intatis`；
- GUI catalog 与 storage key：源码中现有 `intatis.*` identity；
- Swift target/type/path：`Apps/Intatis*`、`Packages/Intatis*`。

不得为显示 Mopelium 品牌创建 `mopelium.json`、`MOPELIUM_*`、`mopelium` CLI 或一套
`MopeliumProviders` / `MopeliumCowork` 镜像。任何内部 identity 迁移都必须由用户单独授权，
并完整评估旧配置、session、catalog、Bundle、CLI 和 durable compatibility。

## 3. Profile 定义与 Agent 绑定

必须使用以下心智模型：

```text
intatis.json/jsonc
  -> mutable provider/model/variant definitions
  -> immutable InferenceCatalog connection/profile revisions
  -> durable AgentInferenceBinding for each Cowork agent
  -> frozen binding in submitted intent / TaskContract

top-level model
  -> future/default data-plane selection

top-level permission_reviewer_model
  -> independently frozen Permission Reviewer base-profile binding
```

- 修改配置只改变可供未来选择的 profile definitions，不重写现有 agent。
- catalog 语义变化创建新 revision；旧 agent 继续引用旧 revision。
- 现有 ordinary agent 只能通过 host-approved、idle-only rebind 改变未来 invocation。
- 当前 queued/running invocation 和 submitted intent 保持原 frozen binding。
- `permission_reviewer_model` 只接受已配置的 `<provider>/<model-id>` base route。字段缺失时只在
  配置解析层一次性继承同一 JSON 文档的顶层 `model`；显式空值、错误类型、无法解析的 route，
  或所选配置整体损坏/不可读，都必须让 reviewer fail closed。
- reviewer 不能回退到 UI/UserDefaults selection、session default、live/historical `@main`、
  `INTATIS_MODEL` 或 ordinary-agent rebind；当前产品也没有 reviewer model picker。
- GoalVerifier 另行冻结首个可解析的 exact `@main` binding；它与 reviewer 是两个独立控制面，
  均不参与普通 agent rebind，也不能互相替代。
- `spawn_agent` 未显式指定 profile 时精确继承 issuer binding，不重新读取 current default。

AI 不得直接编辑 `inference-catalog-v1.json`、`events.jsonl`、`session.json`、outbox、roster、
permission audit 或 task snapshot，也不得猜测 opaque profile/connection/revision/digest。

## 4. 凭据：运行时兼容面与 AI 写入纪律

### 4.1 当前运行时事实

当前 Intatis runtime 的 compatibility surface 包含 environment、file、auth JSON 和 provider-config
reference；macOS/iOS 设置入口也可能把用户主动输入的 secret 写入其受控配置/auth 文件。准确行为
以 `Apps/IntatisMac/Sources/Keychain.swift`、`Apps/IntatisiOS/Sources/Keychain.swift`、
`Packages/IntatisProviders/Sources/Endpoints.swift` 和对应测试为准。

显示品牌决定不改变这套 resolver，也不自动迁移既有用户配置。不得把 runtime compatibility
误写成“当前源码只支持环境变量”。

### 4.2 本仓库 AI 的安全写入规则

AI 仍采用更严格的操作纪律：

- 不读取、打印、记录、比较或摘要任何真实 key；
- 不把 key 写入仓库、文档、测试 fixture、日志、EventLog、UserDefaults 或工具输出；
- 新建配置或在用户明确给出环境变量名时，优先且默认只写 `{env:NAME}`；
- 环境变量名必须匹配 `^[A-Za-z_][A-Za-z0-9_]*$`；
- 不自行把现有 file/auth/provider-config reference 迁成 environment，也不删除它们；
- 不自行创建 auth file、credential file、Keychain item 或含 secret 的备份；
- 发现疑似明文 secret 时只报告字段位置和脱敏问题类型，不复述值；
- 若安全迁移缺少环境变量名，只向用户索取变量名，绝不索取 key 值。

因此，“runtime 可以解析”与“AI 可以主动写入”是两个不同边界。

## 5. 配置发现

macOS 当前顺序：

1. `INTATIS_CONFIG`；
2. `~/.config/intatis/intatis.json`；
3. `~/.config/intatis/intatis.jsonc`；
4. Application Support 下的 `intatis.json` / `intatis.jsonc`；
5. Intatis-owned legacy `config.json` / `config.jsonc` fallback。

CLI modern config 同样优先使用 `INTATIS_CONFIG` 和 Intatis-owned modern paths；精确候选以
`Apps/intatis-cli/Sources/CLIProviderCatalog.swift` 为准。

排障时还要检查以下非秘密 override 是否存在：

- `INTATIS_MODEL`；
- `INTATIS_BASE_URL`；
- `INTATIS_REASONING`。

`INTATIS_API_KEY` 是 legacy/direct CLI secret 输入，只能检查变量是否存在，不得读取、比较或输出
其值。新建 modern provider config 时仍优先使用 `options.apiKey: "{env:NAME}"` 的显式引用。

不得同时修改所有候选配置，也不得为了 Mopelium 显示品牌复制一份新配置树。

## 6. 推荐配置形状

下面只是无秘密占位示例：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "enabled_providers": ["primary-route", "secondary-route"],
  "model": "primary-route/reasoning-model",
  "permission_reviewer_model": "secondary-route/review-model",
  "provider": {
    "primary-route": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Primary Route",
      "options": {
        "baseURL": "https://route-a.example/v1",
        "apiKey": "{env:ROUTE_A_API_KEY}"
      },
      "models": {
        "fast-model": {
          "name": "Fast Model"
        },
        "reasoning-model": {
          "name": "Reasoning Model",
          "options": {
            "reasoning_effort": "medium"
          },
          "variants": {
            "low": { "reasoning_effort": "low" },
            "high": { "reasoning_effort": "high" }
          }
        }
      }
    },
    "secondary-route": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Secondary Route",
      "options": {
        "baseURL": "https://route-b.example/v1",
        "apiKey": "{env:ROUTE_B_API_KEY}"
      },
      "models": {
        "review-model": { "name": "Review Model" }
      }
    }
  }
}
```

`model`、`messages`、`tools`、`stream` 等结构字段由 runtime 拥有，配置不得覆盖。package adapter
identity 必须显式、受支持且保持原值；不得根据 provider 名称猜测 adapter 或 fallback。

## 7. Cowork durable option 边界

Chat/Code 的兼容 endpoint 可以保留更多 model-scoped JSON，但 Cowork 会把 options 编译进
immutable catalog，因此必须使用 `InferenceRequestOptionValidation` 允许的有界 schema。

当前类别包括：

- sampling/token/logprob 数值；
- 少量布尔与安全短字符串；
- 受限 `reasoning`、`thinking`、`output_config`；
- 受限 provider routing 子结构。

以下内容不得进入 Cowork durable options：

- secret、auth、header、query、cookie 或 token；
- URL、endpoint、proxy 或 transport container；
- runtime structural、stream 或多候选控制字段；
- 未进入显式 schema 的 unknown key、错误 shape、过深或过大的结构。

如需支持新的 durable option，先修改 schema 与安全测试，再更新本文；不能只改用户 JSON 就宣称
Cowork 已支持。

## 8. 在 Cowork 中应用配置

通用顺序：

1. 确定唯一实际生效的 Intatis config；
2. 做最小、无秘密的结构修改；
3. 触发 catalog refresh 或重启 CLI；
4. 从安全 UI 或 `/profiles` 获取真实 profile ID；
5. 只通过 host action 设置 future default、创建 agent 或 rebind idle ordinary agent；
6. 查询安全 binding projection；
7. 只有用户明确授权后才发送真实 provider 请求。

macOS Cowork：

- 新 session 的 `@main` 使用创建边界选择的 exact profile；
- runtime 创建边界从 canonical 顶层 `permission_reviewer_model` 独立冻结 reviewer base binding；
  后续 `@main` 或 ordinary-agent rebind 不得重定向 reviewer；
- composer profile selector 只暂存下一次 `@main` submission；
- Send 时冻结 exact binding，FIFO 执行边界才做 main-only durable rebind；
- Project Settings default 只影响未来 agent；
- ordinary agent 的 Rebind 只允许 idle；
- busy/queued/running agent 必须拒绝 rebind。

CLI Cowork 使用现有内部命令：

```text
/profiles
/profile <profile-id>
/agent add <name> <path> [--profile <profile-id>]
/agent profile <name>
/agent rebind <name> <profile-id>
/agent restore-main <path> <profile-id>
```

不得为了 Mopelium 品牌增加第二套 session binding 文件或命令语义。

## 9. Chat、Code 与 Cowork-only 产品方向

当前配置基础设施仍被 Chat、Code 和 Cowork 共享，这是源码事实。Mopelium 的新增产品功能只在
Cowork 建设，并不意味着删除 Chat/Code 的解析兼容或复制一套 Cowork-only provider backend。

- Chat 继续使用当前全局 provider/model/variant selection；
- Code 继续是当前单-agent runtime；
- durable per-agent binding 仍只属于 Cowork；
- 未来隐藏 Chat/Code 只改变用户入口，不改变这些内部配置合同。

## 10. 最低验证

标准 JSON 只检查 parse exit status，不回显内容：

```sh
python3 -m json.tool /absolute/path/to/intatis.json >/dev/null
```

JSONC 必须使用 Intatis loader/catalog refresh 验证。CLI 的无网络配置摘要可使用：

```sh
INTATIS_CONFIG=/absolute/path/to/intatis.json swift run intatis config
```

完整 Cowork catalog 验证通过 macOS refresh 或已获准 session 的 `/profiles`。验证 reviewer 时还必须
确认 canonical 配置中的 `permission_reviewer_model` 成功解析为 exact base profile；不能只看到
`@main` 可用就推断 reviewer 可用。如果操作会创建 session、写 durable state、rebind agent 或发送
网络请求，必须先确认用户授权范围。

修改解析源码或 durable option schema 时至少运行相关 focused tests；只改用户配置时不要把离线
`intatis selftest` 冒充真实 provider E2E。

## 11. 报告合同

配置任务只报告安全元数据：

```text
CONFIG_PATH=<实际生效路径>
CONFIG_CHANGE=<route/model/variant ID>
ENV_REFERENCES=<变量名；无值>
SESSION_BINDING_CHANGE=<none 或安全 agent/profile 变化>
VALIDATION=<命令与 pass/fail>
NETWORK_REQUEST_SENT=<YES/NO>
SECRETS_EXPOSED=NO
```

不得报告 key 值/长度、完整 raw config、credential material、header/query、完整 endpoint audit dump
或 definition digest。

## 12. 当前源码事实源

- `Apps/IntatisMac/Sources/AppConfig.swift`
- `Apps/IntatisMac/Sources/Keychain.swift`
- `Apps/IntatisMac/Sources/AppInferenceCatalog.swift`
- `Apps/intatis-cli/Sources/CLIConfig.swift`
- `Apps/intatis-cli/Sources/CLIProviderCatalog.swift`
- `Apps/intatis-cli/Sources/CLIInferenceProfiles.swift`
- `Packages/IntatisProviders/Sources/Endpoints.swift`
- `Packages/IntatisProviders/Sources/InferenceCatalog.swift`
- `Packages/IntatisProtocol/Sources/InferenceProfile.swift`
- `Packages/IntatisCowork/Sources/Orchestrator.swift`
- `Packages/IntatisCowork/Sources/PermissionReviewControlPlane.swift`
- `docs/PER_AGENT_INFERENCE_PROFILES.md`
