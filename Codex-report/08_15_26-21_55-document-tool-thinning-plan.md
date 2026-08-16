# 文档聚合工具打薄清单

- 报告日期：2026-08-15
- 状态：已实施并完成聚焦验证
- 范围：文档读取、写入、导出、渲染、OCR 与 LaTeX 编译工具
- 本报告记录最终模型工具面、外部 API 对接、已删除聚合层与实际验证结果

## MODEL_CHECK_RESULT

Codex，GPT-5 系列；具体部署标识不可见。

## PATH_CHECK_RESULT

- `pwd`：`/Users/vita/Vitemis/Virgo/Mopelium`
- Git root：`/Users/vita/Vitemis/Virgo/Mopelium`
- 路径符合项目要求。

## FILES_WRITTEN

- 生产实现：`Packages/IntatisTools/Sources/ExactDocumentTools.swift` 及既有文档 backend、contract、
  registry、permission/lease glue 的定向删改。
- 测试：IntatisTools / IntatisProtocol / IntatisCowork 内与文档 contract、backend、registry、lease 直接
  相关的测试。
- 权威文档：`AGENTS.md`、`docs/ARCHITECTURE.md`、`docs/CURRENT_STATE.md`、
  `docs/DO_NOT_BREAK.md`、`docs/OPEN_SOURCE_REUSE.md`、`docs/PROJECT_MAP.md`、`docs/TESTING.md`。
- 本报告：`Codex-report/08_15_26-21_55-document-tool-thinning-plan.md`。

## SUMMARY

目标原则：一个暴露给模型的文档工具，只对应一个固定外部依赖的确定操作。删除模型可选的
`format`、`mode`、`backend`、`operations[]` 和自动 fallback。没有合格外部操作的能力暂不提供，
不自行补写通用解析器、写入 DSL 或格式编排器。

实施结果：旧 `document_ocr` / `document_render` / `document_export_pdf` / `document_write` 均已退出
production registry；standard/Cowork registry identity 已推进到 v6。共用 Swift/Python transport 只保留
hostile-input preflight、路径冻结、source/output CAS、permission/lease、sandbox、timeout、版本 envelope、
单文件安全检查和原子提交，不再解释 `format + mode + operations[]`，也不再执行 preview、Calc recalc、
第二层业务 postcondition verifier 或自动格式分发。

## 聚合工具拆分清单

| 当前聚合工具 | 拆分后的模型工具 | 固定对接的外部工具或 API |
| --- | --- | --- |
| `document_export_pdf` | `docx_export_pdf` | LibreOffice `writer_pdf_Export` |
|  | `pptx_export_pdf` | LibreOffice `impress_pdf_Export` |
|  | `xlsx_export_pdf` | LibreOffice `calc_pdf_Export` |
|  | `html_export_pdf` | WebKit `WKWebView.createPDF` |
| `document_render` | `pdf_render_page` | PDFKit `PDFPage.draw` |
| `document_ocr` | `ocr_pdf` | Docling `DocumentConverter`，固定 Tesseract OCR |
| `compile_latex` | `compile_latex`，只保留一个固定实现 | Tectonic；删除其他编译器探测和回退 |

Office、HTML 渲染不再由一个工具自动完成“导出 PDF + 渲染”。模型必须先调用对应的
`*_export_pdf`，等待结果，再调用 `pdf_render_page`。

## `document_write` 拆分清单

`document_write` 整体退出新会话工具面。删除 `format + mode + operations[]`，改为以下格式专属、
操作专属工具。

### DOCX

| 拆分后的模型工具 | 固定对接的外部 API |
| --- | --- |
| `docx_create_document` | `python-docx Document()` |
| `docx_add_paragraph` | `Document.add_paragraph` |
| `docx_set_paragraph_text` | `Paragraph.text` |
| `docx_add_run` | `Paragraph.add_run` |
| `docx_set_run_bold` | `Run.bold` |
| `docx_set_run_italic` | `Run.italic` |
| `docx_set_run_underline` | `Run.underline` |
| `docx_add_table` | `Document.add_table` |
| `docx_set_table_cell_text` | `_Cell.text` |
| `docx_add_picture` | `Document.add_picture` |
| `docx_set_header_paragraph_text` | header `Paragraph.text` |
| `docx_set_footer_paragraph_text` | footer `Paragraph.text` |
| `docx_set_section_orientation` | `Section.orientation` |
| `docx_set_section_top_margin` | `Section.top_margin` |
| `docx_set_section_right_margin` | `Section.right_margin` |
| `docx_set_section_bottom_margin` | `Section.bottom_margin` |
| `docx_set_section_left_margin` | `Section.left_margin` |

### PPTX

| 拆分后的模型工具 | 固定对接的外部 API |
| --- | --- |
| `pptx_create_presentation` | `python-pptx Presentation()` |
| `pptx_add_slide` | `Slides.add_slide` |
| `pptx_set_shape_text` | `Shape.text` |
| `pptx_add_shape` | `SlideShapes.add_shape` |
| `pptx_add_picture` | `SlideShapes.add_picture` |
| `pptx_add_table` | `SlideShapes.add_table` |
| `pptx_set_table_cell_text` | PPTX table cell `text` |

`pptx_add_slide` 不再同时设置标题；`pptx_add_shape` 不再同时写入文字；`pptx_add_table` 不再同时
填满单元格。后续操作必须等待前一个工具的实际结果。

### XLSX

| 拆分后的模型工具 | 固定对接的外部 API |
| --- | --- |
| `xlsx_create_workbook` | `openpyxl Workbook()` |
| `xlsx_create_sheet` | `Workbook.create_sheet` |
| `xlsx_set_sheet_title` | `Worksheet.title` |
| `xlsx_set_cell_value` | `Cell.value` |
| `xlsx_append_row` | `Worksheet.append` |

### HTML

撤掉当前四个自定义写入操作：

- `xpath.set_text`
- `xpath.set_attribute`
- `xpath.append`
- `xpath.remove`

现有 `lxml` 调用需要组合 XPath 查询、匹配检查、DOM 修改和序列化，不符合一对一原则。在找到成熟的
高层 HTML patch 外部操作前，不提供 HTML 写入工具。

### EPUB

撤掉当前 rbook helper 的聚合 `operations[]`：

- `metadata.set`
- `resource.add`
- `spine.append`
- `toc.add`

没有确认到能够直接对应 rbook 单一公开 API 的 model-facing 操作，因此本轮不提供 EPUB 写入工具。
旧 Swift rbook/EPUBCheck live adapter 与 document backend executable 分支已经删除；已审查的 helper、
EPUBCheck runtime 资产与 provenance 仍保留，但没有 model-facing live route，不能借此恢复聚合写入。

## 不迁移的旧写入操作

| 旧操作 | 处理 |
| --- | --- |
| PPTX `chart.add` | 暂不提供；当前实现需要自行构造 ChartData 和 series DSL |
| XLSX `range.set` | 删除；需要时使用外部已有的 `Worksheet.append` |
| XLSX `style.set` | 删除聚合样式 DSL；只有能直接映射的单个属性才可另设工具 |
| XLSX `table.add` | 暂不提供；当前实现需要自行构造 Table 对象和样式 |
| XLSX `name.set` | 暂不提供；当前实现需要自行构造并注册 DefinedName |
| XLSX `chart.add` | 暂不提供；当前实现是图表构造和引用编排器 |
| HTML 四个 XPath 写入操作 | 暂不提供；没有合格的一对一高层外部操作 |
| EPUB 当前四个写入操作 | 重新核对 rbook API，无法直接对应的全部暂不提供 |

## 读取工具对接清单

模型表面的五种读取工具继续保留，但隐藏后端不再接收通用 `format` 并自行分发。

| 模型工具 | 固定对接的外部工具或 API |
| --- | --- |
| `read_docx` | Docling `DocumentConverter`，固定 DOCX |
| `read_pptx` | Docling `DocumentConverter`，固定 PPTX |
| `read_xlsx` | Docling `DocumentConverter`，固定 XLSX |
| `read_html` | Docling `DocumentConverter`，固定 HTML |
| `read_epub` | Docling `DocumentConverter`，固定 EPUB |
| `read_pdf` | PDFKit |
| `inspect_pdf` | PDFKit |

五个 `continue_*_read` 只负责宿主游标和输出窗口，不重新解析文档，也不选择格式或后端。

## 外部验证工具

| 格式 | 固定外部验证器 |
| --- | --- |
| PDF | `pdfcpu validate --mode strict` |
| EPUB | 当前无 live write route；保留的 EPUBCheck 资产不构成模型工具 |

验证器只做只读格式验证，不自动修改、重写或生成其他文档。

## VALIDATION_RESULT

- `pwd` 与 Git root 核对通过。
- `swift build --target IntatisTools --disable-automatic-resolution`：通过。
- `swift build --target IntatisCowork --disable-automatic-resolution`：通过。
- `swift build --target IntatisToolsTests --disable-automatic-resolution`：通过。
- `DocumentToolContractTests`：9/9，通过。
- `DocumentPythonWriteBackendTests`：8/8，通过。
- `DocumentFixedBackendsTests`、`DocumentReadToolSplitTests`、`PDFNativeDocumentServiceTests`、
  `DocumentInfrastructureTests`、`DocumentToolsIntegrationTests` 共选择 46 个 case：43 个通过、3 个需要
  opt-in 的 smoke 在普通测试轮次按设计跳过、0 failure。全部文档 focused suites 合计 63 个 case：
  60 个通过、3 个跳过、0 failure。
- `CapabilityLeaseTests` 7/7、`MessageDelegationSplitTests` 9/9、`ToolRegistryLeaseTests` 27/27、
  `AgentLoopPolicyTests` 37/37，全部通过。
- 显式启用已安装外部运行时后，exact DOCX create → add paragraph → Docling read → LibreOffice export →
  PDFKit single-page render 1/1，以及 pdfcpu + Docling/Tesseract OCR 1/1，全部通过。
- embedded Python program 语法检查通过；旧 `read` / `ocr` / `write` / `verify_write` route 在依赖导入前
  fail closed。
- `zsh -n scripts/validate-document-runtime.sh`、`zsh -n scripts/package-macos-release.sh`、
  `python3 -m json.tool Packages/IntatisTools/Runtime/document-runtime/release-spec.json` 与最终
  `git diff --check` 均通过。macOS 自带 `plutil -lint` 不接受普通 JSON，未将其作为 JSON gate。
- 未运行整仓全量 SwiftPM test、macOS/iOS App build、Developer ID release、公证、staple、Gatekeeper
  或 clean-machine 验收。
- 工作区开始时已有多项未提交修改和新增文件；本轮没有回退、清理、提交或推送。

## UNCERTAINTIES

- 当前真实外部 runtime smoke 覆盖 exact DOCX 主链与 OCR；PPTX/XLSX 的全部 exact route 已做闭合 schema、
  route、单 mutation 与 fake runner 测试，但未在本轮逐一执行真实 corpus operation matrix。
- rbook 没有本轮确认的一对一 model-facing API，因此 EPUB write 保持不提供，而不是用自写 wrapper 补齐。
- LibreOffice/Docling 等 shipping 双架构签名 runtime 与 clean-machine notarized distribution closure 仍须由
  既有 release gate 证明；开发机 smoke 不能替代发行证据。

## NEXT_RECOMMENDED_ACTION

本清单已经实施。若后续需要增加文档能力，先找到成熟依赖中可直接调用的单一公开 API，再以新 exact
tool 独立评审；没有一对一外部操作就保持不提供。不得恢复通用 `document_write`、隐藏格式分发器、
operations DSL 或顺手扩展当前 surface。
