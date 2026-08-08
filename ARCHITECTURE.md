# Mopelium Architecture

当前产品基线：v0.36（build 36）

Mopelium 是现有 Intatis Cowork 的显示品牌与领域化产品覆盖层；内部架构标识保持 Intatis，
所有新增产品功能只进入 Cowork，Chat/Code 后续只隐藏、不删除。产品边界见
[`docs/MOPELIUM_PRODUCT_DIRECTION.md`](docs/MOPELIUM_PRODUCT_DIRECTION.md)。

此根文件只保留兼容入口。早期 draft-0 架构在 v0.1–v0.3 阶段编写，已经不能描述当前
AgentKernel、durable permission、MCP、Skills、managed terminal、per-agent inference、
AppSessionRuntimeManager 和 iOS 产品边界。

当前架构正文唯一维护在 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。同时参阅：

- [`docs/PROJECT_MAP.md`](docs/PROJECT_MAP.md)：target、入口和关键文件；
- [`docs/DO_NOT_BREAK.md`](docs/DO_NOT_BREAK.md)：不可破坏的协议与安全合同；
- [`docs/COWORK_PRINCIPLES.md`](docs/COWORK_PRINCIPLES.md)：多 agent 编排原则；
- [`docs/MOPELIUM_PRODUCT_DIRECTION.md`](docs/MOPELIUM_PRODUCT_DIRECTION.md)：品牌和 Cowork-only 产品边界；
- [`docs/VERSIONING.md`](docs/VERSIONING.md)：产品版本事实源。

旧 draft 的完整内容仍保留在 Git 历史中，不得再作为当前实现依据。
