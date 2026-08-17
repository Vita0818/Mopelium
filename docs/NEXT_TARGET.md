# NEXT_TARGET

文档状态：当前单一迁移目标
最近核对：2026-08-17
产品基线：v0.10（build 49）

## 目标

完成 Mopelium 内部身份脱钩：当前 package、target、module、App、CLI、路径、配置和新协议输出以 Mopelium 为 canonical identity；唯一 App 是 Bundle ID `com.Vita0818.Mopelium` 的 macOS Developer ID 产品；不保留 iOS App 或 Mac App Store target。

## 执行合同

精确映射、兼容策略、检查项和完成定义见
`docs/MOPELIUM_INTERNAL_IDENTITY_MIGRATION.md`。

## 当前要求

- 同一套 AgentKernel/Cowork/EventLog/permission/runtime 原位迁移，不复制后端；
- Chat/Code 源码、数据兼容和测试保留；
- 新写入只用 Mopelium，旧 Intatis identity 只存在于显式 legacy/history/provenance 边界；
- 不重写历史 EventLog，不削弱权限、workspace、secret、sandbox、签名或恢复不变量；
- 完成 focused/full SwiftPM、XcodeGen、唯一 macOS target、Bundle ID 和静态发行门验证；
- 不自动执行真实 provider、签名、公证、上传、安装或发布。

目标完成后删除本文件或替换为下一个单一目标。
