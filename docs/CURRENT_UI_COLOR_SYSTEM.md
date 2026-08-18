# CURRENT_UI_COLOR_SYSTEM — 淡香槟暖色与无色原生 Liquid Glass

文档状态：当前 UI 实施规范
最近核对日期：2026-08-18
产品基线：v0.12（build 50）

> Mopelium 沿用 `docs/UI_COLOR_SYSTEM.md` 记录的暖中性 / 香槟视觉方向，
> 并以它取代此前“完全交给系统 accent 与 window background”的配色方案。
> 当前值已按实际运行反馈校准：非玻璃层恢复可辨认的淡香槟暖度，所有交互与内容 Glass
> 统一使用 SwiftUI 原生无色 Liquid Glass。品牌色不再进入 `Glass.tint`、按钮 tint 或
> `.glassProminent`；透明材质只从下方暖色 canvas 自然取得环境色。

当前唯一 App 是 macOS `MopeliumMac`。Chat 与 Code 的共享源码仍保留，但当前可见产品入口
只有 Cowork；本文不把历史 iOS surface 当成当前产品或验收矩阵。

## 1. 视觉方向

当前视觉语言是：**可辨认的淡香槟暖色画布 + 克制强调 + 无色系统原生 Liquid Glass**。

1. 暗色界面使用近中性炭灰渐变、柔和灰白正文和低色度淡香槟强调，不使用纯黑页面。
2. 亮色界面使用近白暖灰渐变、深暖墨正文和淡香槟强调，不使用纯白页面。
3. 淡香槟只用于 canvas、品牌、选中、焦点和少量非玻璃强调；不直接染 Glass，不承担状态色。
4. assistant / agent / system 正文直接位于暖色 conversation canvas；只有用户消息拥有普通对话气泡。
5. tool、permission、artifact、Goal、Task 与错误等结构化内容继续使用系统 Material 或专用原生 glass surface。
6. 错误、警告、成功等状态继续使用系统红 / 橙 / 绿，并同时保留图标或文字；淡香槟不替代状态语义。
7. 不恢复旧自绘玻璃。禁止用自绘 blur、高光、折射、阴影、shader 或静态渐变模拟 Liquid Glass。

## 2. 基础颜色令牌

以下 Hex 是 `MopeliumTheme` 中按 sRGB 定义的设计 token，不是截图像素保证。
Material、Glass、窗口状态、显示器 profile 和系统辅助功能仍会影响最终像素。

| 令牌 | 暗色 | 亮色 | 当前用途 |
|---|---:|---:|---|
| `champagne` | `#ECD8BB` | `#ECD8BB` | 高明度淡香槟；暗色强调与暖色基准 |
| `champagneAccent` | `#BCA17F` | `#BCA17F` | 可辨认的暖香槟强调；只用于非玻璃小面积 affordance |
| `deepText` | `#F3EEE7` | `#302A23` | 标题、正文与主要信息 |
| `softText` | `#BFB4A6` | `#736758` | 副标题、说明、非活动控件 |
| `tertiaryText` | `#8E8171` | `#948676` | 占位、时间、低优先级元数据 |
| `glassStroke` | `#CBBBA5` | `#DED0BE` | 暖色 Material / Glass 结构轮廓来源；不是 Glass tint |

### 2.1 页面渐变

`MopeliumSystemCanvas` 从左上到右下绘制三段固定品牌渐变：

| 外观 | 色标 |
|---|---|
| Dark | `#1A1815` → `#211E19` → `#1C1A17` |
| Light | `#FCFAF6` → `#F7EFE3` → `#FBF7F0` |

这些颜色只属于 App detail canvas。macOS sidebar 继续由 `NavigationSplitView` 的系统材质拥有，
不得为了追求完全同色而覆盖自定义侧栏背景。

`MopeliumMacRootView` 同时以 `containerBackground(for: .window)` 把同一
`MopeliumSystemCanvas` 注册为 WindowGroup 的系统容器背景，并隐藏 `.windowToolbar` 自己的 backing。
因此 titlebar/toolbar 仍由 macOS 管理控件、拖拽与窗口状态，但右侧不再回退为系统白色；sidebar
材质仍可独立延伸到左侧 titlebar。

## 3. 语义映射

`MopeliumThreadStyle.mopeliumMac` 是 App 向 SharedUI 注入颜色的语义边界：

| 语义 | Dark | Light | 说明 |
|---|---|---|---|
| `primaryText` | `deepText` | `deepText` | 正文与主要标题 |
| `secondaryText` | `softText` | `softText` | 次要信息 |
| `tertiaryText` | `tertiaryText` | `tertiaryText` | 只读元数据 |
| `accent` | `champagne` | `champagneAccent` | 品牌、选择、活动与焦点；不进入 Glass chrome |
| `stroke` | `glassStroke × 22%` | `glassStroke × 52%` | 去黄后的通用分隔线 |
| `cardStroke` | `glassStroke × 16%` | `glassStroke × 36%` | Material 内容卡轮廓 |
| 所有普通 Glass | 无 tint | 无 tint | 原生 `Glass.regular` / `Glass.clear` / `.glass` |
| destructive Stop | 系统 `.red` | 系统 `.red` | 唯一彩色 glass-button 语义例外 |
| `error` | 系统 `.red` | 系统 `.red` | 错误与破坏性动作 |

Glass 的材质、折射、光照、交互和 active / inactive window 行为全部由系统决定。当前源码不给
Glass 传品牌色，因此不同组件不会因 tint 强度或 `.glassProminent` 再产生金黄 / 无色分叉。

## 4. 原生 Liquid Glass 合同

### 4.1 唯一允许的玻璃实现

- 自定义 view 直接使用 `glassEffect(Glass.regular, in:)` 或
  `glassEffect(Glass.clear, in:)`，需要交互时只追加系统 `.interactive()`。
- 当前系统上的所有非破坏性玻璃按钮统一使用 `.buttonStyle(.glass)`；不得使用
  `.glassProminent` 制造另一种有色 chrome。主要操作层级由位置、label weight、默认键盘动作和
  accessibility 语义表达。
- Stop 继续使用同一 `.glass` 形态与系统 destructive red；这是状态语义，不是品牌 tint。
- 确实需要形变或相邻融合的交互 cluster 才使用 `GlassEffectContainer`。
- macOS 26 以下的 `.regularMaterial` / bordered fallback 只作防御性源码路径；当前产品
  deployment target 与验收面是 macOS 26。

### 4.2 明确禁止

- 不恢复历史 `intatisGlassCard` / `intatisGlassCapsule` 或同类 Mopelium 自绘替代物。
- 不向 `Glass.regular` / `Glass.clear` 调用 `.tint(...)`，也不在 Glass button 的祖先层注入品牌 `.tint`。
- 不手绘玻璃高光、内阴影、折射、噪声纹理、模糊层或动态光源。
- 不用普通 `LinearGradient`、透明圆角矩形或截图资产冒充玻璃。页面品牌渐变是 canvas，
  不是 glass implementation。
- 不把玻璃铺成整页、整段 transcript 或所有普通数据卡。
- 不把彼此独立、位置必须稳定的 Cowork status cards 放进会自动融合 / 重组 shape 的
  `GlassEffectContainer`。

### 4.3 SharedUI 原生 lowering

`MopeliumLiquidGlassModifier` 与 `MopeliumClearLiquidGlassBackdrop` 直接构造系统
`Glass.regular` / `Glass.clear`。SharedUI 不再维护 Glass tint environment key，也不在
`MopeliumThreadStyle` 保存 user/passive tint。

同文件的 `mopeliumSurfaceStroke(_:)` 只为现有 Material / Glass 结构轮廓注入暖色
`cardStroke`，不替换或着色系统 surface。根视图统一设置它，避免业务 View 重复硬编码描边。

## 5. 表面与组件映射

| 层级 | 当前实现 | 颜色 / 材质职责 |
|---|---|---|
| Detail canvas | `MopeliumSystemCanvas` | 近中性炭灰或近白暖灰三段渐变 |
| Sidebar | `NavigationSplitView` 原生 sidebar | 系统 vibrancy / active-window；文字和 controls 使用主题语义 |
| Conversation text | 直接继承 detail canvas | assistant / agent / system、Markdown、代码与公式 |
| User message | 无色原生 `Glass.regular` | 唯一普通对话气泡，trailing 对齐，无自定义 stroke |
| Structured content | `.regularMaterial` + 暖色语义 outline | tool、permission、artifact、Goal / Task 与错误内容 |
| Functional glass | 无色 native regular glass / `.glass` buttons | composer、模型菜单、选择控件、主要操作 |
| Cowork status rail | 独立无色 `Glass.clear` | permission、Agents、Goal、Tasks、条件式错误卡 |

### 5.1 页面与侧栏

- detail 始终显示当前 Light / Dark 的暖色渐变。
- sidebar 不设置 `MopeliumTheme.canvas` 或自定义 fill；模式图标、标题、session 选中态与
  Settings 使用主题文字、accent 和 native interactive Glass。
- window toolbar backing 必须隐藏，并由 `.window` container background 下的同一暖色 canvas 接管；
  不得在 titlebar 另画白色/纯色矩形，也不得用 NSWindow 私有接线替代 SwiftUI 官方容器 API。
- 当前选中模式与 ordinary agent 的 affordance 使用淡香槟，不再描述为系统蓝色或金黄色。

### 5.2 对话

- 用户消息保持 trailing、既有最大宽度与 gutter，使用无色原生 `Glass.regular`；暖度来自 canvas。
- assistant / agent / system 没有外层卡片、Material 或描边；失败 / 中断时已产生的正文也保持该规则。
- 正常 tool、permission、artifact 和 task 是结构化内容，不适用“只有用户有气泡”的普通消息规则。
- Code / Cowork 的 error、失败 trace、recovery 和失败 submission 继续只进入右栏唯一条件式错误卡。

### 5.3 Composer 与 controls

- 共享 composer 保持两排布局、40pt input / action 几何、voice 紧邻唯一 Send/Stop 和 bottom alignment。
- model/profile label 与输入容器使用无 tint 的原生 interactive Glass。
- attachment、voice、New、Send 与普通 actions 全部使用同一种 native `.glass`；不再使用
  `.glassProminent`。Send 的主要层级由位置、图标、默认动作与可访问性表达。
- Stop 保持同一 Glass 形态，但继续使用系统 destructive red。

### 5.4 Cowork rail

- rail 仍是同一 detail canvas 上的 trailing overlay，不创建整栏背景或 divider。
- permission、Agents、Goal、Tasks 与错误卡各自使用稳定、无 tint 的原生 `Glass.clear` backdrop。
- rail 的 348pt / 318pt 固定几何、10pt scroller clearance、Equatable boundary、单 ScrollView
  和无坐标回写合同不因配色变化而改变。

### 5.5 Material cards 与状态色

- `.regularMaterial` 继续通过下方暖色 canvas 取得环境混色；结构边界使用暖色 `cardStroke`。
- error / destructive 使用系统 red；pending / blocked 使用系统 orange；completed 使用系统 green。
- 淡香槟只表达品牌、active 与 selected；running/completed/failed 等状态继续使用系统语义和文字。

## 6. 代码事实来源

- `Apps/MopeliumMac/Sources/MopeliumDesign.swift`：固定 sRGB token、Light/Dark 页面渐变、
  macOS semantic style 与 Material 卡片描边。
- `Apps/MopeliumMac/Sources/MopeliumMacRootView.swift`：system sidebar、detail canvas、`.window`
  container background、透明 window-toolbar backing 与统一结构描边。
- `Packages/MopeliumSharedUI/Sources/ThreadSurfaces.swift`：无 tint 的原生 Glass lowering、统一
  `.glass` button style 与 `mopeliumSurfaceStroke`。
- `Packages/MopeliumSharedUI/Sources/Views.swift`、`CodeViews.swift` 和
  `Apps/MopeliumMac/Sources/MopeliumChatScreen.swift`：三个无色用户消息 Glass 入口。
- `Packages/MopeliumSharedUI/Sources/CoworkViews.swift`：无色 passive rail Glass。
- `docs/UI_COLOR_SYSTEM.md`：重新启用的 palette 来源及旧实现 provenance；旧类型名和自绘玻璃
  描述不是当前源码事实。

## 7. 可访问性与对比度

- `deepText` 负责正文；淡香槟不作为长正文色，避免在浅色背景上承担不足的文本对比度。
- `tertiaryText` 只用于时间、占位和低优先级元数据；关键信息必须使用 primary / secondary 层级。
- active、pending、failed、completed 等状态必须同时有文字、图标或结构，不可只靠色相区分。
- Reduce Transparency、Increase Contrast、active / inactive window、focus、hover 与按压光学继续由
  原生 Material / Glass / control API 处理；不得以固定截图效果覆盖系统响应。
- Light、Dark、Reduce Transparency、Increase Contrast、键盘焦点和 VoiceOver 必须作为运行态
  验收项；源码使用语义结构不等于这些场景已经自动通过。

## 8. 验收清单

- Light detail 是近白暖灰渐变，Dark detail 是近中性炭灰渐变；两者都没有纯白 / 纯黑页面底。
- sidebar 保留系统 `NavigationSplitView` 材质，窗口 active / inactive 时仍由系统响应。
- titlebar/toolbar 右侧与 detail 使用同一暖色 window canvas，不得出现系统白色横条；左侧继续显示
  sidebar 自有系统材质。
- canvas、品牌和选中 affordance 呈可辨认的淡香槟暖度；Glass chrome 本身无色，不得出现棕黄。
- 所有非破坏性 Glass button 使用同一 `.glass`，没有 `.glassProminent` 或祖先品牌 tint；Stop red 是唯一状态例外。
- 只有用户普通消息有外层气泡，且能确认其为无 tint 的 native `Glass.regular`。
- Cowork rail 各 card 是独立、无 tint 的 native `Glass.clear`；没有整栏自绘表面。
- composer、model menu、New、voice、Send/Stop 的既有几何、focus、keyboard 与 accessibility
  identifier 不因颜色改动而变化。
- 搜索 active source 时，不存在历史自绘玻璃 modifier、shader、高光或阴影实现。
- `MopeliumSharedUI` focused build/tests 与 `MopeliumMac` unsigned Debug build 通过。
- 运行态至少核对 macOS Light 与 Dark；未检查的辅助功能或硬件环境必须标为 `UNKNOWN`。

建议静态复核：

```sh
rg -n 'intatisGlass|mopeliumGlassCard|visualEffectBlur|shadow.*glass' Apps Packages
rg -n 'Glass\.(regular|clear)\.tint|buttonStyle\(\.glassProminent|mopeliumNativeGlassTint' \
  Apps/MopeliumMac Packages/MopeliumSharedUI
rg -n 'Glass\.(regular|clear)|glassEffect|buttonStyle\(\.glass|LinearGradient' \
  Apps/MopeliumMac Packages/MopeliumSharedUI
rg -n 'Color\.(white|black)|Color\(\.sRGB|#[0-9A-Fa-f]{6}' Apps Packages
```

第三条命中必须人工确认：当前允许的固定品牌 token 只能集中在 `MopeliumTheme`；图像、PDF、
测试 fixture 或系统状态色不属于 UI theme token。

## 9. 历史边界

- 2026-08-18 之前的 `CURRENT_UI_COLOR_SYSTEM.md` 版本记录了完全动态的 system window / accent 方案；
  它已被本规范取代，只能从 Git 历史读取。
- `UI_COLOR_SYSTEM.md` 的颜色和视觉方向重新成为当前来源，但其中 Intatis 文件路径、旧 iOS
  映射、`intatisGlassCard` / `intatisGlassCapsule` 与自定义玻璃透明度算法仍是历史事实。
- 本次视觉切换不修改字体、布局、EventLog、provider、权限、Agent 编排、session runtime 或分发边界。
- 未引入第三方源码、图片、字体、Logo、shader 或其他视觉资产；App 图标直接使用
  用户提供的 PNG 原始字节，仅由 Icon Composer 以 scale 0.95 接线，因此 `NOTICE.md` 无需更新。

## 10. 本次验证记录

- `swift build --target MopeliumSharedUI --disable-automatic-resolution`：通过；仅有既有
  `onChange(of:perform:)` deprecation warning。
- 原生 Glass surface 接线完成后，`swift test --filter MopeliumSharedUITests
  --disable-automatic-resolution` 曾完整通过 153 tests、0 failures。淡香槟低色度校准后再次运行该
  target 时，runner 在编译完成后长期无输出，约 4.5 分钟后人工中断，不将其计作通过或源码失败；
  统一无色 Glass 与 window-toolbar 修复后运行直接覆盖 user-only native glass、composer、rail、
  geometry、chrome 一致性与窗口背景接线的
  `swift test --filter ThreadLayoutTests --disable-automatic-resolution`：23 tests、0 failures；
  `testCurrentGlassChromeIsColorlessAndUnified` 明确禁止 Glass tint、`.glassProminent` 与祖先品牌 tint，
  `testWindowToolbarUsesTheWarmWindowCanvas` 固定 `.window` container background 和透明 toolbar backing。
- `swift build --disable-automatic-resolution`：通过。
- `xcodegen generate`：通过；生成 `Mopelium.xcodeproj`。
- `xcodebuild -quiet -jobs 4 -project Mopelium.xcodeproj -scheme MopeliumMac
  -configuration Debug -destination 'platform=macOS' COMPILER_INDEX_STORE_ENABLE=NO
  CODE_SIGNING_ALLOWED=NO build`：通过（exit 0）；只有仓库既有 warning，以及 Xcode 在若干成功
  SwiftCompile 后打印的“command failed with exit code 0”噪音。
- App/CLI 已改为 canonical-only Application Support：在本机 canonical 与 legacy 根同时存在的
  默认环境中，`MCPCLIProcessOwnerTests.testShippingCodeStartupWithoutMCPAddsNoMCPStdout`
  直接通过（1 test、0 failures），无需 `CFFIXED_USER_HOME`。排除 `TESTING.md` 已记录的两项
  provider retry 基线冲突后，同一默认环境完整 SwiftPM command 最终 exit 0；真实
  provider/browser/document-runtime 等 opt-in tests 按设计 skipped。未删除、合并或修改任一
  Application Support 根。
- active source 静态扫描确认 `Glass.regular.tint`、`Glass.clear.tint`、
  `mopeliumNativeGlassTint` 与 `.glassProminent` 均为零命中；允许的当前实现只有
  `Glass.regular` / `Glass.clear`、`glassEffect`、统一 `.glass` button style 与 canvas
  `LinearGradient`，且没有历史自绘玻璃 modifier 命中。
- 使用 `computer-use` Skill 检查本轮 Debug App：Light 模式 Settings 与用户截图中的
  “确认空白 HTML 画布”会话均显示暖色 titlebar/detail 连续，右侧系统白条已消失，sidebar 材质、
  traffic lights 与 toolbar control 保持原生。Dark、Reduce Transparency、Increase Contrast、
  VoiceOver 与窗口 active/inactive 切换仍为 `UNKNOWN`。
