# AI_PROVIDER_MODEL_CONFIGURATION

最后更新：2026-07-26

## 1. 受众与用途

本文只面向负责维护 Mopelium 的 AI coding / operations agent。它不是终端用户教程，也不授权 AI 获取、查看、迁移或输出任何 API key。

当任务涉及以下任一事项时，AI 必须先读本文：

- 新增或修改 provider route；
- 新增 model、model options 或 variant；
- 配置同一 Cowork session 中不同 agent 使用不同 model/profile；
- 修改 API-key 环境变量引用；
- 排查“配置已改，但现有 agent 仍使用旧模型”；
- 排查 CLI 与 macOS 对同一配置文件的解析差异。

本文中的 **MUST / MUST NOT / SHOULD** 是执行约束。若本文与当前源码、测试或 `docs/DO_NOT_BREAK.md` 冲突，以当前源码和更严格的安全约束为准，并在报告中指出冲突。

## 2. 先区分“定义 profile”与“绑定 agent”

AI 必须使用以下心智模型：

```text
mopelium.json/jsonc
  -> mutable provider/model/variant definitions
  -> immutable InferenceCatalog connection/profile revisions
  -> durable AgentInferenceBinding for each Cowork agent
  -> frozen binding in each TaskContract / submitted intent
```

配置文件负责定义可供选择的 profile 池，不负责保存某个现有 agent 的实时绑定。

- 修改配置文件不会重写现有 `@main`、worker、queued/running task 或控制面 agent。
- catalog refresh 会为语义变化创建新 revision；旧 agent 继续引用旧 revision。
- 将某个 agent 切换到新 profile 必须走 host 提供的显式 attach/rebind/submission 流程。
- 当前 invocation 已冻结的 binding 不会被中途修改。

AI MUST NOT 直接编辑以下派生或 durable 文件来“配置模型”：

- `inference-catalog-v1.json`；
- Cowork `events.jsonl`；
- `session.json`；
- `submitted-intent-outbox.json`；
- 任何 agent roster、permission audit 或 task snapshot。

AI MUST NOT 猜测 opaque profile ID、connection ID、revision、variant digest 或 definition digest。它们必须由 Mopelium 编译并通过安全 UI/CLI 投影取得。

## 3. 凭据规则

### 3.1 唯一允许的配置形式

真实凭据只允许由 Mopelium 进程从环境变量读取。配置中只能出现变量名引用：

```json
"apiKey": "{env:ROUTE_A_API_KEY}"
```

环境变量名必须匹配：

```text
^[A-Za-z_][A-Za-z0-9_]*$
```

每个 route SHOULD 显式声明自己的环境变量引用。若多个 route 有意共享同一个环境变量，可以显式写成相同名称；否则不得依赖隐式默认。

### 3.2 永久禁止

AI MUST NOT：

- 读取、打印、记录、摘要或比较环境变量的实际值；
- 把真实 key 写进 JSON/JSONC、UserDefaults、文档、日志、测试 fixture、`.env`、auth JSON、普通文件或 Keychain；
- 写入明文 `apiKey` / `api_key` / `api-key`；
- 使用 `{file:...}`、`apiKeyFile`、`authFile`、`providerConfig`、`credentialRef`、`apiKeyRef` 或其他非环境凭据来源；
- 把 header、query、URL user-info 或 URL query parameter 当作鉴权载体；
- 为了验证配置而回显完整配置文件，因为旧文件可能已经包含不安全内容。

如果 AI 发现疑似明文 secret 或非环境 credential reference，必须：

1. 不复述其值或路径；
2. 只报告字段位置和“已脱敏”的问题类型；
3. 只有在用户已指定安全环境变量名时才做最小替换；
4. 否则停止凭据迁移，要求用户提供变量名，而不是要求提供 key 值。

`MOPELIUM_API_KEY_ENV` 是全局变量名选择器。CLI 加载 modern config 时，它可能覆盖 route 自己的变量名选择。多 route 配置中，除非确实要求所有 route 共用同一个变量，AI SHOULD 保持该全局选择器未设置，并在每个 route 中显式写 `options.apiKey`。

## 4. 选择要修改的配置文件

### 4.1 共享 modern 配置

macOS 与 CLI 共同支持 `mopelium.json` / `mopelium.jsonc`。新建配置时使用：

```text
~/.config/mopelium/mopelium.json
```

若任务需要临时或项目专属配置，可由宿主把 `MOPELIUM_CONFIG` 指向一个明确的绝对路径。AI 不得自行把配置复制进仓库，除非用户明确要求仓库内 fixture/example。

### 4.2 发现顺序

macOS：

1. `MOPELIUM_CONFIG` 指定的文件；
2. `~/.config/mopelium/mopelium.json`；
3. `~/.config/mopelium/mopelium.jsonc`；
4. `~/Library/Application Support/Mopelium/mopelium.json`；
5. `~/Library/Application Support/Mopelium/mopelium.jsonc`；
6. `~/.config/mopelium/config.json`；
7. `~/.config/mopelium/config.jsonc`；
8. `~/Library/Application Support/Mopelium/config.json`；
9. `~/Library/Application Support/Mopelium/config.jsonc`。

CLI modern config：

1. `MOPELIUM_CONFIG` 指定的文件；
2. `~/.config/mopelium/mopelium.json`；
3. `~/.config/mopelium/mopelium.jsonc`；
4. `~/Library/Application Support/Mopelium/mopelium.json`；
5. `~/Library/Application Support/Mopelium/mopelium.jsonc`。

AI SHOULD 修改两个产品面都能读取的 modern 文件，不应为新配置选择旧 `config.json`。旧 `~/.config/mopelium/config.json` 仍可供 CLI 单 route 兼容路径读取，但不是多 route / Cowork profile 的规范目标。

若多个候选文件同时存在，AI 必须先按上述顺序确定实际生效文件；不得同时修改所有候选文件。

### 4.3 其他 host override

配置文件不是唯一输入。AI 在排障时必须同时确认是否存在以下非秘密 override，但不得打印其 secret value：

- `MOPELIUM_CONFIG`：选择配置文件；
- `MOPELIUM_MODEL`：CLI 当前 model override；
- `MOPELIUM_BASE_URL`：CLI 当前 selected route 的 endpoint override；
- `MOPELIUM_API_KEY_ENV`：API-key 环境变量名的全局选择器；
- `MOPELIUM_REASONING`：CLI reasoning variant 选择。

不要自动 unset 或改写用户的进程环境。发现 override 与文件冲突时，只报告优先级和影响。

## 5. 规范配置形状

AI 新建共享配置时 SHOULD 使用下列 snake_case 顶层字段和 camelCase provider option。示例中的 route、model、URL 和环境变量名都是占位数据，不是可用凭据：

```json
{
  "enabled_providers": [
    "primary-route",
    "secondary-route"
  ],
  "model": "primary-route/fast-model",
  "provider": {
    "primary-route": {
      "name": "Primary Route",
      "options": {
        "baseURL": "https://route-a.example/v1",
        "chatEndpoint": "https://route-a.example/v1/chat/completions",
        "apiKey": "{env:ROUTE_A_API_KEY}"
      },
      "models": {
        "fast-model": {
          "name": "Fast Model",
          "options": {
            "temperature": 0.2
          }
        },
        "reasoning-model": {
          "name": "Reasoning Model",
          "options": {
            "reasoning_effort": "medium"
          },
          "variants": {
            "low": {
              "reasoning_effort": "low"
            },
            "high": {
              "reasoning_effort": "high"
            }
          }
        }
      }
    },
    "secondary-route": {
      "name": "Secondary Route",
      "options": {
        "baseURL": "https://route-b.example/v1",
        "apiKey": "{env:ROUTE_B_API_KEY}"
      },
      "models": {
        "review-model": {
          "name": "Review Model"
        }
      }
    }
  }
}
```

不要仅为了本教程添加第三方 `$schema`、package 名或品牌元数据。解析器不要求这些字段。若既有文件包含未知的非秘密元数据，AI SHOULD 最小修改并保留它；若字段可能承载 credential/transport override，则必须按安全规则拒绝或清理。

## 6. 字段合同

| 字段 | AI 写入规则 |
|---|---|
| `enabled_providers` | 可选 allowlist。非空时只加载列出的 route。使用配置中的真实 route ID。 |
| `disabled_providers` | 可选 denylist；与 enabled 冲突时 disabled 生效。 |
| `model` | Chat/Code 与新 Cowork session 的默认选择输入，不是现有 agent binding。简单 ID 推荐写成 `providerID/modelID`。 |
| `provider` | 必需对象；key 是本地 route ID。使用稳定、简短、无秘密的 ID。 |
| `provider.<id>.name` | 可选安全展示名。不得含 URL、credential、账号或内部 secret label。 |
| `provider.<id>.options.baseURL` | 每个可用 route 必需。共享给 Cowork 时必须是带 host、无 user-info/query/fragment 的绝对 `http`/`https` URL。 |
| `provider.<id>.options.chatEndpoint` | 可选完整 chat endpoint；省略时由 base URL 推导。共享给 Cowork 时同样不得含 user-info/query/fragment。 |
| `provider.<id>.options.apiKey` | 只能是 `{env:NAME}`。每个 route 建议显式写。 |
| `provider.<id>.models` | CLI/Cowork 共享配置中必须非空。key 默认就是发送给 provider 的 model ID。 |
| model 字符串值 | 可简写为展示名，例如 `"model-id": "Display Name"`。需要 options/variants 时使用对象。 |
| model `name` / `displayName` | 可选展示名；不改变请求 model ID。 |
| model `id` | 可覆盖 map key 作为请求 model ID；除非兼容既有配置，否则 SHOULD 省略，避免 key 与真实 ID 分叉。 |
| model `options` | model 基础请求参数。共享给 Cowork 时必须满足 durable allowlist。 |
| model `variants` | 命名预设 map。每个 variant 的对象本身就是覆盖参数，不再嵌套 `options`。 |
| variant `disabled` | `true` 时该 variant 不进入可选 profile；编译前会移除该控制字段。 |

顶层 `model` 的解析先尝试在所有启用 route 中按完整 model key 精确匹配，再尝试解释为 `providerID/modelID`。因此 model ID 本身含 `/` 时，AI 必须检查是否唯一；跨 route 同名且无法由当前 route 消除歧义时，使用明确的 provider-qualified 选择并通过 loader 验证。

## 7. Cowork durable options allowlist

Chat/Code 的兼容 `ProviderEndpoint` 路径会保留更多任意 model JSON；Cowork 会把同一配置编译进 durable immutable catalog，因此限制更严格。只要配置可能用于 Cowork，AI SHOULD 按 Cowork 子集编写。

当前允许的顶层 canonical 拼写：

- 数值：`temperature`、`top_p`、`top_k`、`min_p`、`typical_p`、`frequency_penalty`、`presence_penalty`、`repetition_penalty`、`seed`、`max_tokens`、`max_completion_tokens`、`max_output_tokens`、`max_new_tokens`、`top_logprobs`；
- 布尔：`logprobs`、`parallel_tool_calls`；
- 安全短字符串：`reasoning_effort`、`verbosity`、`service_tier`；
- 受限对象：`reasoning`、`thinking`、`output_config`、`provider`。

受限对象当前允许：

```text
reasoning:
  effort, summary, max_tokens, budget_tokens, enabled

thinking:
  type, level, budget_tokens, max_tokens, enabled

output_config:
  effort, verbosity

provider:
  allow_fallbacks, require_parameters, zdr
  sort, data_collection
  order, only, ignore, preferred, quantizations
  max_price
```

源码会对大小写和常见分隔符做 normalized-key 比较，但 AI SHOULD 使用上面的 canonical snake_case 拼写。

以下内容不得进入 Cowork durable model/variant options：

- 未知 key、过深/过大对象或错误 JSON 类型；
- `model`、`messages`、`tools`、`stream` 等 runtime structural fields；
- `stream_options`；
- `n`、`best_of`、`num_return_sequences`、`candidate_count` 等多候选控制；
- secret/auth/header/query/cookie/token 字段；
- URL、base URL、endpoint、proxy 或 transport container；
- 任意未进入 `InferenceRequestOptionValidation` 显式 schema 的新厂商字段。

若业务确实需要新 durable option，AI MUST NOT 直接把它塞进配置并宣称可用。正确流程是先修改 `InferenceRequestOptionValidation`、补充 schema/安全测试，再更新本文。

## 8. 三种多模型配置模式

### 8.1 同一 route，不同 model

在同一个 `provider.<id>.models` 下声明多个 model。它们共享 connection 与环境变量引用，但会编译为不同 profile。适合让 `@main` 使用 reasoning model、worker 使用 fast model。

### 8.2 同一 model，不同 variant

在一个 model 下声明 `variants`。variant 只覆盖请求参数，不改变发送给 provider 的 model ID。适合 low/medium/high reasoning 或不同 token/sampling 预设。

### 8.3 不同 route

声明多个 `provider.<id>`，每个 route 使用自己的 base URL、可选 chat endpoint 和环境变量引用。即使两个 route 使用同名 model，它们也会形成不同 connection/profile revision。

当前 shipped resolver 只支持 OpenAI-compatible wire。配置多个 route 不代表已经实现其他 wire adapter、fallback、负载均衡或跨 trust-domain route lease。

## 9. 把配置应用到真实 Cowork session

### 9.1 通用顺序

AI 应按以下顺序执行：

1. 修改实际生效的 modern 配置文件；
2. 触发 app catalog refresh，或重启会在启动时读取配置的 CLI；
3. 从安全 UI 或 CLI `/profiles` 获取编译后的 profile ID；
4. 再通过 host action 选择 future default、创建 agent 或 rebind idle agent；
5. 查询 agent 的安全 binding 投影确认结果；
6. 只在用户授权后发送真实 provider 请求。

写盘成功不等于 session 中所有 agent 已切换。

### 9.2 macOS Cowork

- 新 Cowork session：当前 provider/model/variant 选择成为 fresh `@main` 的 exact profile。
- composer 底部 model/profile selector：只暂存下一次 `@main` submission；选择动作本身不 rebind。
- 按 Send：把当时的 exact binding 冻结进该 submission；FIFO 到执行边界时才进行 main-only durable rebind。
- Project Settings 的 default profile：只影响未来新 agent。
- Agent inference profiles 的 `Rebind…`：只用于 ordinary idle agent。
- busy/queued/running agent：rebind 必须被拒绝；AI 不得通过改 EventLog 绕过。
- `@permission-reviewer` 与 GoalVerifier：是冻结的控制面，不是普通 rebind 目标。

### 9.3 CLI Cowork

使用以下 host commands，不直接编辑 session 文件：

```text
/profiles
/profile [profile-id]
/agent add <name> <path> [--profile <profile-id>]
/agent profile <name>
/agent rebind <name> <profile-id>
/agent restore-main <path> <profile-id>
```

语义：

- `/profiles`：列出安全、host-approved profiles；
- `/profile <id>`：修改未来 agent default，不重写现有 agent；
- `/agent add ... --profile`：创建时显式绑定；
- `/agent add ...`：使用 future-agent default；
- `/agent profile`：查看安全 binding；
- `/agent rebind`：host-only、idle-only，只影响未来 invocation；
- `/agent restore-main`：只用于 non-empty recovered session 缺失 `@main` 的显式修复；
- Cowork `/model`：只读兼容展示，不改写 agent route。

spawn 未显式指定 profile 时，子 agent 精确继承 issuer 的完整 binding，而不是重新读取当前 default。

### 9.4 Chat 与 Code

- Chat 使用当前全局 provider/model/variant selection；
- Code 是单 agent 产品面；
- durable per-agent binding 和同 session 多 agent profile 只属于 Cowork。

AI 不得把“配置文件里有多个 model”误报成 Chat/Code 已拥有 per-agent routing。

## 10. AI 修改流程

### 10.1 修改前

1. 核对当前工作目录、仓库规则和用户授权范围。
2. 只检查环境变量是否存在及其变量名；不读取值。
3. 按发现顺序确定唯一生效配置文件。
4. 判断任务是：
   - 只定义 provider/model/variant；
   - 修改默认选择；
   - 还是还要求绑定某个现有 Cowork agent。
5. 检查目标文件是否含疑似 literal secret；不得在工具输出中打印文件全文。

### 10.2 修改时

1. 做最小结构化修改，保留不相关的非秘密字段和用户注释。
2. 使用明确 route ID、model ID 和环境变量名。
3. 对共享配置采用 Cowork durable allowlist。
4. 不创建重复 route/model key。
5. 不改 `inference-catalog-v1.json` 或 session durable state。
6. 原子写入，并把配置权限保持为 owner-only `0600`。
7. 不把配置副本、备份或 diff 写入仓库，因为旧文件可能含敏感历史。

### 10.3 修改后

1. 先做语法与结构验证；
2. 再做 Mopelium loader/catalog 验证；
3. 确认只展示变量名、route/profile safe label 和 model ID；
4. 若用户只要求写配置，到此停止，不自动 rebind 或发送请求；
5. 若用户明确要求同 session 多 agent，继续走 host-approved attach/rebind，并逐 agent 核对安全 binding。

## 11. 验证

### 11.1 不泄密的最低验证

对标准 JSON，可只检查 parse exit status，不把格式化内容写到终端：

```sh
python3 -m json.tool /absolute/path/to/mopelium.json >/dev/null
```

JSONC 必须用 Mopelium 的 JSONC loader 或 app config refresh 验证；标准 JSON 工具不理解 comments/trailing commas。

在目标 route 的环境变量已由宿主安全注入、但不显示其值的前提下，可运行：

```sh
MOPELIUM_CONFIG=/absolute/path/to/mopelium.json swift run mopelium config
```

该命令用于验证实际文件发现、selected route/model 和基础解析，并只输出安全摘要；它不应发起 provider 网络请求。它不能替代全部 Cowork durable option 编译验证。

完整 Cowork catalog 验证应通过 macOS catalog refresh，或在已获准使用的 CLI Cowork session 中查看 `/profiles`。如果该操作会创建新 session 或写 durable state，必须先确认它属于用户授权范围。不要仅以 `mopelium selftest` 作为目标配置通过的证据；selftest 使用自己的离线 fixture。

若修改了配置解析源码或 durable option schema，而不只是用户配置文件，还必须运行相关自动化：

```sh
swift test --filter InferenceCatalogTests
swift test --filter InferenceCatalogStoreResolverTests
swift test --filter PerAgentInferenceProfileTests
swift run mopelium selftest
```

### 11.2 结果检查

验证至少回答：

- 实际加载的是哪个配置路径；
- 启用了哪些 route ID；
- 每个目标 model/variant 是否进入安全 profile 列表；
- 每个 route 引用哪个环境变量名；
- 目标 agent 当前绑定哪个安全 profile/model/variant；
- 是否发生显式 rebind；
- 当前/queued task 是否保持原 frozen binding；
- 是否发起了网络请求。

不得回答：

- API key 值或长度；
- raw endpoint 的 durable audit dump；
- 完整 options、credential ref、header/query；
- 完整 definition digest。

## 12. 常见失败与处置

| 现象 | AI 处置 |
|---|---|
| 配置文件已改，现有 agent 仍显示旧 model | 这是预期的 immutable binding 行为。刷新 catalog 后对 idle ordinary agent 显式 rebind。 |
| agent 正在 running/queued，rebind 被拒绝 | 不绕过。等待其 idle，或让用户决定是否取消当前工作；当前 task 保持 frozen binding。 |
| route 环境变量缺失 | 只报告缺失的变量名，不索取、不打印 key。 |
| `apiKey` 是明文或 file/auth reference | fail closed；替换为用户指定的 `{env:NAME}`，否则停止。 |
| model ID 在多个 route 中歧义 | 使用 provider-qualified selection，或让用户选择 route；不得随机取第一个。 |
| variant 不出现在 `/profiles` | 检查 `disabled`、JSON shape 和 durable option allowlist。不得合成 synthetic effort profile。 |
| unknown option 被 Cowork 拒绝 | 对照 `InferenceRequestOptionValidation`。没有源码/schema 变更时不得宣称支持。 |
| retained old agent revision 无法解析 | 不 fallback 到当前 default 或同名 model；由 host 显式修复/rebind。 |
| 修改 data-plane agent 后 reviewer 未变化 | 这是控制面冻结行为。普通 rebind 不得 retarget reviewer/GoalVerifier。 |
| CLI 与 macOS 选择不同 | 检查实际配置路径和 host overrides，尤其 `MOPELIUM_CONFIG`、`MOPELIUM_MODEL`、`MOPELIUM_API_KEY_ENV`。 |

## 13. AI 最终报告合同

完成配置任务后，AI 应只报告安全元数据：

```text
CONFIG_PATH=<实际生效路径>
CONFIG_CHANGE=<新增/修改的 route、model、variant ID>
ENV_REFERENCES=<环境变量名列表；无值>
SESSION_BINDING_CHANGE=<none / 具体 agent 的安全 profile 变更>
VALIDATION=<命令与 pass/fail>
NETWORK_REQUEST_SENT=<YES/NO>
SECRETS_EXPOSED=NO
```

若真实多 route/model 网络调用尚未执行，必须明确写“结构/catalog 验证通过，真实 provider E2E 未验证”，不能用离线测试替代。

## 14. 当前源码事实源

修改本教程或排查解析行为时，至少核对：

- `Apps/MopeliumMac/Sources/AppConfig.swift`：macOS config discovery、JSON/JSONC、provider/model/variant 解析和 owner-only 写入；
- `Apps/MopeliumMac/Sources/Keychain.swift`：environment-only secret resolver；
- `Apps/MopeliumMac/Sources/AppInferenceCatalog.swift`：app config 到 immutable profile 的编译；
- `Apps/mopelium-cli/Sources/CLIConfig.swift`：CLI override 优先级；
- `Apps/mopelium-cli/Sources/CLIProviderCatalog.swift`：modern config、route/model/variant 与 environment credential 解析；
- `Apps/mopelium-cli/Sources/CLIInferenceProfiles.swift`：CLI profile 编译；
- `Packages/MopeliumProviders/Sources/InferenceCatalog.swift`：durable option schema 与 exact catalog；
- `Packages/MopeliumProtocol/Sources/InferenceProfile.swift`：安全 binding；
- `Packages/MopeliumCowork/Sources/Orchestrator.swift`：attach/spawn/rebind/invocation 语义；
- `docs/PER_AGENT_INFERENCE_PROFILES.md`：完整 durable per-agent inference 契约。
