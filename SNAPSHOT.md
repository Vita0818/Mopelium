# Intatis 根基线快照

## 来源

- 来源目录：`/Users/vita/Vitemis/Intatis`
- 来源 Git root：`/Users/vita/Vitemis/Intatis`
- 分支：`main`
- commit：`2d849dbe592a4532a23d0b5a0f84c4e52e459505`
- commit 标题：`v0.37`
- commit 时间：`2026-08-06T12:13:50+08:00`
- 快照内 `project.yml` 产品版本：`0.36 (build 36)`；commit 标题不是产品版本事实源
- 复制前状态：clean
- 快照创建时间：`2026-08-06T12:31:37+08:00`
- 提升为仓库根基线：`2026-08-06`

## 复制合同

当前仓库根目录 `/Users/vita/Vitemis/Virgo/Mopelium` 不是只读参考，而是用户指定的后续实现、构建和测试活动基线。后续变更应直接落在仓库根目录，不再维护或仿照任何嵌套快照，也不得改写来源仓库。

快照从上述 commit 的 Git 受控内容生成，因此没有复制源 `.git/` 或任何未跟踪的本地文件。另按父仓库安全规则排除了源 commit 中的 `codex-report/` 与 `gemini-report/`；源树未包含其他顶层已跟踪报告目录。

以下类别不得通过后续刷新带入：

- Git 元数据、构建缓存和生成物；
- report/test-result 目录；
- 应用运行态、受管 worktree 和浏览器 profile；
- 环境文件、认证文件、密钥、证书和 provisioning profile；
- 任何未被用户明确授权复制的私有或凭据数据。

当前基线没有嵌套 Git 仓库。版本控制、diff、status、构建与测试都以 Git root `/Users/vita/Vitemis/Virgo/Mopelium` 为工作目录。

快照提升到根目录时，所有非文档内容均由快照替换；文档以快照版本为主，并额外保留快照中不存在的两个 Mopelium 项目文档：

- `docs/AI_PROVIDER_MODEL_CONFIGURATION.md`
- `docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md`

提升后另建立 `docs/MOPELIUM_PRODUCT_DIRECTION.md` 固定产品覆盖层决策：用户可见品牌采用
Mopelium，内部 Intatis 标识保持不变，新增产品功能只进入 Cowork，Chat/Code 后续只隐藏、不删除。
该决策不改变本文件记录的快照来源，也不表示相应 UI 已经实施。

## 创建时验证

- 来源受控文件数：716
- 来源目录数（写入本文件前）：135
- 来源快照磁盘占用（写入本文件前）：约 15 MB
- 嵌套 `.git/`：不存在
- 已排除报告目录：不存在
- 环境/认证/密钥/证书/provisioning 常见敏感文件名扫描：0 命中
- Git submodule：0
- Git symlink：0

快照采用来源 HEAD 的 Git archive 直接展开；未复制来源工作区的 5.2 GB Git、缓存和其他本地数据。根基线提升未修改快照业务源码，只适配了本文件与根 `AGENTS.md` 的仓库路径说明，并保留上述两个项目独有文档。

## 刷新规则

不得自动追踪或同步来源目录。只有用户明确要求刷新时，才重新核对来源 root、分支、commit、工作区状态与敏感排除项，并更新本文件；刷新不得覆盖当前快照中尚未提交或尚未明确处置的用户改动。
