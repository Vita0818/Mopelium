# Intatis 根基线快照

## 来源

- 来源目录：`/Users/vita/Vitemis/Intatis`
- 来源 Git root：`/Users/vita/Vitemis/Intatis`
- 分支：`main`
- commit：`120eda64fcb098f1bdc4852fee886450e80b3722`
- commit 标题：`v0.54`
- commit 时间：`2026-08-14T23:35:48+08:00`
- 快照内 `project.yml` 产品版本：`0.48 (build 48)`；commit 标题不是产品版本事实源
- 复制前来源工作树状态：clean
- 本次快照创建时间：`2026-08-14T23:44:06+08:00`
- 当前根基线首次建立：`2026-08-06`

## 复制合同

当前仓库根目录 `/Users/vita/Vitemis/Virgo/Mopelium` 是用户指定的后续实现、构建和测试活动基线，
不是只读参考。后续变更直接落在本仓库根目录；不维护嵌套快照，不把变更写回来源仓库，也不在
两个仓库之间做隐式同步。

本次刷新从上述 exact commit 的 Git tree 生成 archive 并直接展开到当前仓库根目录。目标仓库自己的
`.git/` 保留；来源 `.git/`、来源未跟踪文件、构建缓存、生成物和本地运行态均未复制。来源 commit
中受控的 `codex-report/` 与 `gemini-report/` 共 50 个报告文件按父仓库安全规则排除。

以下类别不得通过后续刷新带入：

- 来源 Git 元数据、构建缓存和生成物；
- 来源 report/test-result 目录；
- 应用运行态、受管 worktree 和浏览器 profile；
- 环境文件、认证文件、密钥、证书和 provisioning profile；
- 任何未被用户明确授权复制的私有或凭据数据。

当前根目录已有的 ignored/local build state（例如 `.build/`、`.intatis/`、`.swiftpm/` 和生成的
`Intatis.xcodeproj`）不属于快照，也未作为来源复制对象。本次验证已用新 `project.yml` 重新运行
`xcodegen generate`，因此当前生成工程与 `0.48 (48)` 元数据一致；其余缓存仍可能来自旧基线，
正式构建时必须让构建系统重验依赖，不得把这些本地生成物当作快照证据。

## Mopelium 专属文档保留范围

受控源码、测试、配置、资源以及 Intatis 通用文档均由来源快照替换。以下当前项目专属文档保留，
并在需要时按新源码事实适配：

- `AGENTS.md`
- `SNAPSHOT.md`
- `docs/MOPELIUM_PRODUCT_DIRECTION.md`
- `docs/AI_PROVIDER_MODEL_CONFIGURATION.md`
- `docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md`
- `Codex-report/COWORK_BROWSER_PERMISSION_CONTINUATION_INCIDENT_2026-08-07.md`
- `Codex-report/COWORK_PERMISSION_REVIEW_CONTEXT_INCIDENT_AND_MINIMAL_REVISION_2026-08-08.md`

其中 `docs/INTATIS_MULTI_AGENT_MIGRATION_AUDIT.md` 与两份 `Codex-report/` 文档只作为历史记录保留；
若它们与当前源码、测试、构建配置或 `docs/MOPELIUM_PRODUCT_DIRECTION.md` 冲突，以后者为准。

## 来源 gitlink 边界

来源 commit 含 26 个 mode `160000` gitlink。Git archive 只保留相应空目录结构，不包含这些外部
仓库的工作树或 `.git/`；本快照也不把它们变成 nested repository。冻结时在 `Package.swift`、
`project.yml`、`Makefile` 和 `scripts/` 中没有发现 `OpenSource/` 路径引用，因此当前受控的
SwiftPM/XcodeGen/脚本构建图不直接消费这些 checkout。gitlink 指针记录如下：

- `OpenSource/Open-XML-SDK` @ `cd2b359ef824737edb93f1c6157c19551aae1e52`
- `OpenSource/PaddleOCR` @ `2661c7c0ef5c613e8f93c6e93b2e052399f0f854`
- `OpenSource/PptxGenJS` @ `3c9ec1b687c174952166f6a34b5e87ebf69fa469`
- `OpenSource/Sigil` @ `05bf67cd73f05d9d3aae50920223f2c19231f5a4`
- `OpenSource/apache-poi` @ `bbf2e879c36fcd837fd1e7579f9f82cfba88883e`
- `OpenSource/calibre` @ `94b9cf8a80930fc61bfc92c7ded08abdb3c224f3`
- `OpenSource/daisy-ace` @ `dfa87b528f598a034f98e8a3126bf4b5bf9203bf`
- `OpenSource/docling` @ `8050c42be2b179504445cb8f3c75655e27cbb662`
- `OpenSource/docling-mcp` @ `7b51926920550c4a2c6e888977b8e38a08bafdbd`
- `OpenSource/docx4j` @ `74ea74323a33d92769fdbd3e6d5fe730bbfd8ffb`
- `OpenSource/epub.js` @ `eee359d0790002115a1156a9833c54f4bcd44c1d`
- `OpenSource/epubcheck` @ `82b174ec319ea3e6c9d2488f84155fa4a9171fc2`
- `OpenSource/libreoffice-core` @ `88771d0a64e06297b7f82d6cc00cdf0d60c199cc`
- `OpenSource/mcp-swift-sdk` @ `a0ae212ebf6eab5f754c3129608bc5557637e605`
- `OpenSource/msoffcrypto-tool` @ `6d9e72c58de2cf7df1ab45ac0d74ebedac8c58e3`
- `OpenSource/noto-cjk` @ `f8d157532fbfaeda587e826d4cd5b21a49186f7c`
- `OpenSource/pdfbox` @ `bbea338208b7712bc151e2ff507764552eff03ad`
- `OpenSource/pdfcpu` @ `c9c07d0fcd19439f967cfff96203ebe41a1e8327`
- `OpenSource/pdfium` @ `e9fc01804a0c5224ea780ad782abb8cfede628ef`
- `OpenSource/pixelmatch` @ `c6fee35afac3c52576b2cb424bd1061ab6a4bd06`
- `OpenSource/python-docx` @ `e45454602b53e8e572b179ccf1c91093ec9f4ed7`
- `OpenSource/python-pptx` @ `278b47b1dedd5b46ee84c286e77cdfb0bf4594be`
- `OpenSource/qpdf` @ `8ff6b5c4fca59e38b147aebddeb54341fc313ed1`
- `OpenSource/rbook` @ `d440c7cf35db2fd31e938c0555448dbaec5437d0`
- `OpenSource/tessdata` @ `ced78752cc61322fb554c280d13360b35b8684e4`
- `OpenSource/tesseract` @ `64ed93b68c01f359d924fc1bfcf0d5931eb77211`

## 创建时验证

- 来源受控普通文件数：877
- 排除的来源报告文件数：50
- 实际 materialize 的来源普通文件数：827
- archive 目录数（含根目录和 26 个空 gitlink 目录）：176
- materialized 文件总字节：16,948,164（约 17 MB；`du` 约 18 MB）
- 来源 Git symlink：0
- 来源 gitlink：26；外部工作树与 nested `.git/` 均未复制
- archive 内 nested `.git/`：0
- 环境/认证/密钥/证书/provisioning 常见敏感文件名扫描：0 命中
- 来源 `.agents/` 与目标保留版本逐字节一致；因目标目录受保护而未重复写入

来源 commit 还包含一个名为 `:-` 的 253-byte 根文件，其内容是代码签名 requirement 文本；该文件
属于 exact Git tree，因此随快照保留。此处只记录文件性质，不复制其内容到项目文档。

## 刷新规则

不得自动追踪或同步来源目录。只有用户明确要求刷新时，才重新核对来源 root、分支、commit、
工作区状态、gitlink 和敏感排除项，并更新本文件。刷新前必须先处置当前仓库未提交改动；不得覆盖、
回退或清理用户尚未明确授权处置的工作。
