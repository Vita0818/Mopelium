# UI_COLOR_SYSTEM — 香槟金配色来源与历史实现记录

文档状态：当前配色来源；旧实现细节仍按历史语境保留
重新启用：2026-08-18
历史语境核对：2026-08-03

> **本文中的暖中性色与香槟方向继续作为来源，但旧金色数值不再是当前 token。**
>
> 当前实现以 `CURRENT_UI_COLOR_SYSTEM.md` 为精确规范：原方案已按用户运行反馈校准为
> 非玻璃层可辨认的淡香槟暖度，以及统一无色的 Glass chrome；同时不恢复
> `intatisGlassCard` / `intatisGlassCapsule` 等自定义玻璃实现。所有玻璃继续使用
> SwiftUI 原生 `Glass.regular` / `Glass.clear`、`glassEffect` 与 glass button style，
> 但不再调用 `Glass.tint`、注入祖先 button tint 或使用 `.glassProminent` 制造有色分支。

本文正文中“上一版”“当前源码”“迁移前”等措辞仍以 2026-07-14 的历史快照为语境，
用于保存原方案的 provenance 与旧组件映射；它们不表示旧的自绘玻璃代码重新成为事实。
当前 token 用法、无色原生 Glass、组件边界与验收清单只看 `CURRENT_UI_COLOR_SYSTEM.md`
和源码。

本文保留的固定 RGB/Hex、页面渐变与品牌金只作为历史 provenance；当前实际数值以
`CURRENT_UI_COLOR_SYSTEM.md` 为准。旧自绘玻璃、旧 target/类型名和历史 iOS 映射仍只用于对照，
不得据此恢复。

## 1. 重新启用的视觉方向

macOS 当前沿用的视觉语言是：**淡香槟暖色底 + 非玻璃强调 + 无色系统原生 Liquid Glass 层次**。

- 大面积背景保持暖黑、暖白和低饱和中性色，不用金色铺满界面。
- 淡香槟主要表示 canvas、品牌、选中和非玻璃强调，不染 Glass chrome，也不替代状态色。
- 正文使用暖墨色而非纯黑/纯白，次级文字降低明度和对比度。
- 卡片、输入区、用户气泡和 rail 通过无色原生 Glass、暖色环境 canvas、细描边及系统 Material 建立层次。
- 成功、等待和失败仍使用系统语义色，避免用品牌金承担所有状态含义。

上一版暗色界面的总体观感是暖黑棕背景、石墨色玻璃侧栏、象牙白文字、低饱和沙金用户气泡和深色玻璃助手气泡；亮色模式对应为暖白、奶油色描边与深暖墨文字。

## 2. 源码事实来源

以下文件是上一版配色在当前源码中的事实来源，按优先级排列；它们不是下一版配色的设计依据：

1. `Apps/IntatisMac/Sources/IntatisDesign.swift`：macOS 品牌色、明暗模式、渐变、玻璃修饰器与字体。
2. `Packages/IntatisSharedUI/Sources/ThreadSurfaces.swift`：跨平台 thread 语义色和 iOS 使用的标准样式。
3. `Apps/IntatisMac/Sources/IntatisMacRootView.swift`、`IntatisChatScreen.swift`：侧栏、选择态、聊天气泡、composer 和设置页的实际使用。
4. `Packages/IntatisSharedUI/Sources/CodeViews.swift`、`CoworkViews.swift`、`Views.swift`：Code/Cowork 状态色及 iOS Chat 行的实际使用。

## 3. 上一版 macOS 基础颜色令牌

下表中的 Hex 是源码 RGB 分量按 sRGB 方式换算的设计令牌值。带透明度或 Material 的最终屏幕像素不会等于这个 Hex，详见“新配色迁移约束”。

| 令牌 | 暗色模式 | 亮色模式 | 主要用途 |
|---|---:|---:|---|
| `gold` | `#C9A86A` | `#C9A86A` | 标准香槟金、强调描边、警告描边、渐变终点 |
| `goldSoft` | `#D8BE86` | `#D8BE86` | 高光、柔和选择底、品牌渐变起点 |
| `goldDeep` | `#B5934F` | `#B5934F` | 强调文字、选中图标、按下/运行中状态 |
| `sand` | `#EFE6D2` | `#EFE6D2` | 用户气泡的浅沙色基底 |
| `deepText` | `#ECE4D4` | `#2B2620` | 标题、正文和主要信息 |
| `softText` | `#ADA288` | `#7A7064` | 副标题、说明、非活动控件 |
| `tertiaryText` | `#6E6552` | `#A89E8C` | 占位、弱提示、未知或取消状态 |
| `glassSurface` | `#1B1811` | `#FFFFFF` | 玻璃卡片、侧栏、助手气泡的底色基值 |
| `glassStroke` | `#8D7648` | `#F1EAD8` | 暖金/奶油玻璃边缘基值 |
| `shadow` | 系统黑色 | `#B59C6B` | 玻璃层阴影基值 |

### 3.1 页面背景渐变

`pageGradient` 从左上到右下：

| 模式 | 色标顺序 |
|---|---|
| 暗色 | `#17150F` → `#1F1C14` → `#1A1710` |
| 亮色 | `#FBF9F4` → `#F4EFE3` → `#FAF6EE` |

上一版品牌按钮的 `accentGradient` 同样从左上到右下，色标为 `#D8BE86` → `#C9A86A`，迁移前源码中的按钮文字使用白色。

## 4. 上一版 macOS 语义色映射

在上一版实现中，`IntatisThreadStyle.intatisMac` 是 Chat、Code、Cowork 共用界面消费的语义层。

| 语义字段 | 暗色模式 | 亮色模式 | 用途 |
|---|---|---|---|
| `primaryText` | `deepText` | `deepText` | 主要文字 |
| `secondaryText` | `softText` | `softText` | 次要文字 |
| `tertiaryText` | `tertiaryText` | `tertiaryText` | 弱提示和默认状态 |
| `accent` | `goldDeep` | `goldDeep` | 选中、活动和强调 |
| `accentSoft` | `goldSoft` × 24% | `goldSoft` × 45% | 选择态和弱强调背景 |
| `surface` | `glassSurface` | `glassSurface` | 表面基色 |
| `stroke` | `glassStroke` × 50% | `glassStroke` × 85% | 通用边框 |
| `userBubble` | `sand` × 16% | `sand` × 85% | 用户消息气泡 |
| `assistantBubble` | `glassSurface` × 30% | `glassSurface` × 70% | 助手消息气泡 |
| `cardSurface` | `glassSurface` × 28% | `glassSurface` × 64% | 卡片、面板、统计胶囊 |
| `cardStroke` | `glassStroke` × 40% | `glassStroke` × 70% | 卡片边框 |
| `warningSurface` | `goldSoft` × 16% | `goldSoft` × 20% | 警告背景 |
| `warningStroke` | `gold` × 32% | `gold` × 42% | 警告边框 |
| `error` | 系统 `.red` | 系统 `.red` | 错误、失败和破坏性操作 |
| `material` | `.ultraThinMaterial` | `.ultraThinMaterial` | 玻璃模糊和环境混色 |

“× 24%”表示对该基色应用 SwiftUI `opacity(0.24)`，不是独立、不透明的新 Hex。

## 5. 上一版组件使用记录

本节记录旧实现如何使用颜色，不是新方案必须继承的设计规则。

### 5.1 页面、侧栏与选择态

- macOS 根页面使用 `pageGradient`。
- 侧栏等大面积容器使用低透明度 `glassSurface` 叠加系统 Material，保持中性，不使用大块实心金色。
- 通用 mode segment 的选中底使用 `accentSoft`，选中图标/文字使用 `accent`。
- Settings 选中底使用 `goldSoft`：暗色 22%，亮色 36%；选中描边使用 `gold`：暗色 34%，亮色 42%。
- Provider 选中底使用 `goldSoft`：暗色 22%，亮色 32%；选中描边使用 `gold` 55%。
- hover、未选中和禁用态在上一版中使用玻璃表面与次级文字，不会升级为主金色操作态。

### 5.2 消息、卡片与输入区

- 用户消息使用右对齐的 `userBubble`；助手消息使用左对齐的 `assistantBubble` 并叠加 `.ultraThinMaterial`。
- Code/Cowork 卡片、Goal/Tasks、Agent 和 Git 状态区使用 `cardSurface` / `cardStroke`，不自行发明固定灰色。
- Composer、模型菜单和统计胶囊使用玻璃表面；边框保持细、低对比，焦点或选择时才增加金色提示。
- 主要提交按钮使用 `accentGradient`；次级按钮使用玻璃胶囊或语义文字色。
- 错误、权限拒绝和破坏性操作使用系统红色，不能只靠金色或低对比文字表达。

### 5.3 玻璃修饰器

`intatisGlassCard` 和 `intatisGlassCapsule` 会在 `glassSurface` 之上叠加 Material、渐变描边和阴影。暗色模式还会收窄不透明度：

- fill：`min(传入值 × 0.82, 0.40)`；
- stroke：`min(传入值 × 0.72, 0.34)`；
- 暗色卡片阴影：`max(传入阴影 × 0.5, 0.08)`。

因此复现或分析上一版玻璃表面时，应通过这些修饰器或语义样式理解，不能把截图取色值当成原始令牌。

## 6. 上一版状态色

状态色是语义提示，不是品牌装饰。上一版 Cowork 的主要映射如下：

| 状态 | 颜色 |
|---|---|
| `active`、`in_progress`、`running`、`thinking`、`tool` | `accent` / `goldDeep` |
| `assigned`、`paused`、`pending`、`queued`、`ready`、`mailbox` | 系统 `.orange` |
| `blocked`、`budget_limited`、`usage_limited` | 系统 `.orange` |
| `completed`、`complete`、`done` | 系统 `.green` |
| `failed`、`error`、`rejected` | `error` / 系统 `.red` |
| 未知、默认、取消 | `tertiaryText` |

Code 中的低/中/高风险也分别使用系统 `.green` / `.orange` / `.red`。这些系统颜色会随平台、显示模式和可访问性设置变化，本文不为它们声明固定 Hex。

## 7. 上一版字体与颜色搭配

- 英文品牌名和大标题：系统 Serif，配 `deepText`。
- 正文、中文和操作文字：系统字体，主要内容用 `deepText`，说明用 `softText`。
- 代码、路径和技术令牌：系统 Monospaced，按信息层级使用主要或次级文字色。
- 不使用颜色作为唯一的信息通道；状态应同时保留图标、标签或文字。

## 8. 上一版时期的 iOS 配色

截至上一版方案记录时，iOS 没有直接使用 `IntatisTheme`，而是使用 `IntatisThreadStyle.standard(scheme)` 和系统 `accentColor`。因此 iOS 与 macOS 的组件结构部分共享，但品牌配色没有完全统一。

| iOS 语义字段 | 迁移前源码实现 |
|---|---|
| 主要/次要文字 | 系统 `.primary` / `.secondary` |
| 第三级文字 | `.secondary` × 72% |
| 强调色 | 系统或宿主配置的 `.accentColor`，无固定 Hex |
| 弱强调色 | `.accentColor` × 16% |
| 暗色表面 | RGB `0.12 / 0.12 / 0.12`，约 `#1F1F1F` |
| 亮色表面 | `#FFFFFF` |
| 用户气泡 | `.accentColor`：暗色 18%，亮色 12% |
| 助手气泡 | surface：暗色 30%，亮色 70% |
| 卡片表面 | surface：暗色 26%，亮色 62% |
| 卡片描边 | `.secondary`：暗色 22%，亮色 14% |
| 警告 | 系统 `.yellow`：背景暗色 14%/亮色 10%，描边 38% |

共享 iOS Chat 的 `MessageRow` 在迁移前源码中仍直接使用：用户 `.accentColor` 12%，其他角色 `.gray` 10%，tag 使用 `.accentColor` 及其 14% 背景。这是旧实现当前事实，不应误写成 macOS 香槟金主题已经覆盖 iOS，也不表示下一版必须保留系统强调色。

## 9. 当前重新启用边界

- SwiftUI Material、透明度、窗口后方内容、系统 vibrancy、显示器色彩管理都会影响最终像素；本文 Hex 是源令牌，不是截图像素保证。
- 当前固定品牌 RGB 只能集中在 `MopeliumTheme`；业务 View 不得散落新 Hex、截图采样值或用 `.white` / `.black` 绕过主题语义。
- 本文提供 palette 来源，不单独决定当前组件实现。准确的无色 native Glass、Material、消息、composer、rail 和 sidebar 映射以 `CURRENT_UI_COLOR_SYSTEM.md` 与源码为准。
- 重新启用香槟方向不等于恢复旧自绘玻璃。`intatisGlassCard` / `intatisGlassCapsule` 的 fill/stroke/shadow 算法仍是历史记录；当前 Glass 只允许系统未着色的 `Glass.regular` / `Glass.clear` 与 `.glass` button style。
- macOS titlebar/toolbar 使用 SwiftUI 官方 `.window` container background 与透明 toolbar backing
  露出同一暖色 canvas；不得恢复系统白条、另画 titlebar 表面或用 AppKit 私有窗口接线复制该能力。
- 跨平台组件仍应接收语义样式并由平台注入，不得让 SharedUI 反向依赖 macOS target。
- 当前唯一 App 是 macOS；历史 iOS 表格不构成产品面或验收矩阵。
- 至少检查暗色、亮色、提高对比度和降低透明度场景；关键信息不能只通过色相区分。
- 配色变化必须同步更新本文、`CURRENT_UI_COLOR_SYSTEM.md`、`CURRENT_STATE.md`、`PROJECT_MAP.md` 与相关视觉验证记录。

## 10. 仍未固定的部分

- 系统 Material 与原生 Liquid Glass 在不同 macOS 版本、设备、窗口状态和辅助功能设置下的最终混色值未固定。
- 当前 Glass 固定为无 tint；系统如何从下方暖色 canvas 产生高光、折射、模糊和交互反馈仍不是 Mopelium 的像素合同。
- Display P3、HDR、特定显示器 profile 下的像素差异未建立独立基准。
- 本文不替代布局、交互、动态字体和完整无障碍规范；精确当前实施合同仍以 `CURRENT_UI_COLOR_SYSTEM.md` 为准。
