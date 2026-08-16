# Intatis document runtime release contract

The document tools use external document engines; Intatis does not implement
DOCX, PPTX, XLSX, HTML, EPUB, or OCR parsers. Ordinary reads are performed by
the pinned Docling public converter/serializer/chunker APIs. Explicit PDF OCR
uses the pinned Docling PDF pipeline and Tesseract. The remaining fixed tools
use PDFKit, LibreOffice, pdfcpu, rbook, and EPUBCheck only for their declared
roles.

`release-spec.json` is the repository-owned compatibility contract. It is not
a binary runtime and must not be treated as one. A releasable runtime is built
outside the source tree for each supported architecture and has this layout:

```text
<architecture-root>/
  runtime-manifest.json
  SHA256SUMS.txt
  bin/python3
  bin/tesseract
  bin/pdfcpu
  bin/intatis-rbook-helper
  bin/intatis-epubcheck
  jre/temurin-21.0.11+10/Contents/Home/bin/java
  lib/epubcheck-5.3.0/
  libreoffice/26.8.0.0.beta1/LibreOffice.app/
  models/docling/docling-project--docling-layout-heron/
  share/tessdata/{eng,chi_sim,chi_tra,jpn,kor,fra,deu,spa,ita,por,osd}.traineddata
  ThirdPartyNotices/runtime.spdx.json
  ThirdPartyNotices/LICENSES.txt
  ThirdPartyNotices/licenses/
```

`runtime-manifest.json` repeats `schema_version`, `layout_version`,
`runtime_release`, `components`, and `maximum_resident_bytes` from the release
spec and adds the exact `architecture`. `SHA256SUMS.txt` must inventory every
regular file except the inventory itself, using lowercase SHA-256 followed by
two spaces and a `./` relative path. Symlinks may only resolve within their
architecture root. The release validator additionally compares the exact
project-owned EPUBCheck wrapper, the three runtime Heron model files, and all
allowlisted Tesseract language data against repository-owned SHA-256 values;
model-card images and cache metadata are not shipped.

The SBOM and license bundle must describe the complete resolved distribution,
including Python itself, every wheel and native library, model/data licenses,
the JRE, Tesseract/tessdata, LibreOffice and its bundled components, pdfcpu,
EPUBCheck, and the rbook helper closure. Direct package metadata or a `pip
freeze` file is not a substitute for this transitive inventory.
The automated gate checks valid SPDX-2.3 document metadata, a non-empty
package array, the license bundle, and exact file inventory. Those structural
checks do not prove that an SBOM author found every transitive component;
release review must compare the SBOM and license texts with the resolved
binary closure before accepting either architecture root.

Before `scripts/package-macos-release.sh` accepts a runtime, every Mach-O in
both architecture roots must already be signed bottom-up with the same
Developer ID identity used for the outer App and with any reviewed nested
entitlements preserved. Mach-O load commands may reference only Apple system
libraries or bundle-relative `@loader_path`, `@executable_path`, and `@rpath`
locations; build-machine/Homebrew/user-framework absolute dependencies and
non-system absolute `LC_RPATH` values are rejected. The release script first
validates both roots without executing their contents, before and after
staging them at:

```text
Intatis.app/Contents/Resources/DocumentRuntime/arm64
Intatis.app/Contents/Resources/DocumentRuntime/x86_64
```

Only after the outer App has been signed and its strict resource seal and
exact Developer ID identity have been verified does the second validation
phase execute fixed version probes. Those probes use the target architecture
with an empty environment and validation-owned temporary `HOME`/`TMPDIR`.
Direct `execute` mode is rejected unless the runtime is already inside that
verified final App layout.

At runtime the active universal-app slice selects only its matching root. A
CLI or debug build may still use the historical user-managed runtime as an
explicit development fallback; that fallback never satisfies the App release
gate. The tools remain offline and subject to WorkspaceLease, Seatbelt,
timeout/cancellation, process-tree cleanup, output bounds, and the independent
2 GiB aggregate resident-memory ceiling.
