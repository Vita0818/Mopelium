#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
spec="$project_root/Packages/MopeliumTools/Runtime/document-runtime/release-spec.json"
runtime_root="${1:-}"
expected_architecture="${2:-}"
expected_signing_identity="${3:-}"
validation_mode="${4:-static}"
temporary_root=""

fail() {
    print -u2 -- "error: $*"
    exit 1
}

cleanup() {
    if [[ -n "${temporary_root:-}" && -d "$temporary_root" ]]; then
        /bin/rm -rf -- "$temporary_root"
    fi
}
trap cleanup EXIT

[[ -n "$runtime_root" && -n "$expected_architecture" ]] \
    || fail "usage: scripts/validate-document-runtime.sh <runtime-root> <arm64|x86_64> [Developer ID identity] [static|execute]"
[[ "$expected_architecture" == "arm64" || "$expected_architecture" == "x86_64" ]] \
    || fail "runtime architecture must be arm64 or x86_64"
[[ "$validation_mode" == "static" || "$validation_mode" == "execute" ]] \
    || fail "validation mode must be static or execute"
[[ "$runtime_root" == /* ]] || fail "runtime root must be an absolute path"
[[ -d "$runtime_root" && ! -L "$runtime_root" ]] || fail "runtime root is missing or is a symlink"
runtime_root="$(cd "$runtime_root" && pwd -P)"

manifest="$runtime_root/runtime-manifest.json"
inventory="$runtime_root/SHA256SUMS.txt"
[[ -f "$spec" && ! -L "$spec" ]] || fail "repository document runtime release spec is missing"
[[ -f "$manifest" && ! -L "$manifest" ]] || fail "runtime manifest is missing or unsafe"
[[ -f "$inventory" && ! -L "$inventory" ]] || fail "runtime SHA-256 inventory is missing or unsafe"
/usr/bin/plutil -convert xml1 -o /dev/null "$spec" \
    || fail "repository document runtime release spec is not valid JSON"
/usr/bin/plutil -convert xml1 -o /dev/null "$manifest" \
    || fail "runtime manifest is not valid JSON"

json_value() {
    /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null \
        || fail "missing JSON field $2 in ${1:t}"
}

for key in schema_version layout_version runtime_release maximum_resident_bytes; do
    [[ "$(json_value "$manifest" "$key")" == "$(json_value "$spec" "$key")" ]] \
        || fail "runtime manifest $key does not match the release spec"
done
[[ "$(json_value "$manifest" architecture)" == "$expected_architecture" ]] \
    || fail "runtime manifest architecture does not match $expected_architecture"

components=(
    python docling docling_slim docling_core docling_parse python_docx
    python_pptx openpyxl lxml pypdfium2 tesseract tessdata_fast pdfcpu
    epubcheck temurin_jre libreoffice docling_layout_model
    rbook_helper_protocol
)
for component in $components; do
    [[ "$(json_value "$manifest" "components.$component")" \
        == "$(json_value "$spec" "components.$component")" ]] \
        || fail "runtime component $component does not match the release spec"
done

required_files=(
    bin/python3
    bin/tesseract
    bin/pdfcpu
    bin/mopelium-rbook-helper
    bin/mopelium-epubcheck
    lib/epubcheck-5.3.0/epubcheck.jar
    jre/temurin-21.0.11+10/Contents/Home/bin/java
    models/docling/docling-project--docling-layout-heron/config.json
    models/docling/docling-project--docling-layout-heron/model.safetensors
    models/docling/docling-project--docling-layout-heron/preprocessor_config.json
    share/tessdata/eng.traineddata
    share/tessdata/chi_sim.traineddata
    share/tessdata/chi_tra.traineddata
    share/tessdata/jpn.traineddata
    share/tessdata/kor.traineddata
    share/tessdata/fra.traineddata
    share/tessdata/deu.traineddata
    share/tessdata/spa.traineddata
    share/tessdata/ita.traineddata
    share/tessdata/por.traineddata
    share/tessdata/osd.traineddata
    ThirdPartyNotices/runtime.spdx.json
    ThirdPartyNotices/LICENSES.txt
)
for relative_path in $required_files; do
    [[ -f "$runtime_root/$relative_path" && ! -L "$runtime_root/$relative_path" ]] \
        || fail "runtime is missing required regular file $relative_path"
done
required_directories=(
    models/docling
    share/tessdata
    ThirdPartyNotices/licenses
    libreoffice/26.8.0.0.beta1/LibreOffice.app
)
for relative_path in $required_directories; do
    [[ -d "$runtime_root/$relative_path" && ! -L "$runtime_root/$relative_path" ]] \
        || fail "runtime is missing required directory $relative_path"
done
for executable in \
    bin/python3 \
    bin/tesseract \
    bin/pdfcpu \
    bin/mopelium-rbook-helper \
    bin/mopelium-epubcheck \
    jre/temurin-21.0.11+10/Contents/Home/bin/java; do
    [[ -x "$runtime_root/$executable" ]] || fail "runtime executable is not executable: $executable"
done
runtime_spdx="$runtime_root/ThirdPartyNotices/runtime.spdx.json"
/usr/bin/plutil -convert xml1 -o /dev/null "$runtime_spdx" \
    || fail "runtime SPDX SBOM is not valid JSON"
[[ "$(json_value "$runtime_spdx" spdxVersion)" == "SPDX-2.3" ]] \
    || fail "runtime SBOM must use SPDX-2.3"
[[ "$(json_value "$runtime_spdx" dataLicense)" == "CC0-1.0" ]] \
    || fail "runtime SBOM dataLicense must be CC0-1.0"
[[ "$(json_value "$runtime_spdx" SPDXID)" == "SPDXRef-DOCUMENT" ]] \
    || fail "runtime SBOM must identify the document as SPDXRef-DOCUMENT"
[[ -n "$(json_value "$runtime_spdx" documentNamespace)" ]] \
    || fail "runtime SBOM has no document namespace"
spdx_package_count="$(
    /usr/bin/plutil -extract packages raw -expect array -o - "$runtime_spdx" 2>/dev/null
)" || fail "runtime SBOM packages field is missing or is not an array"
[[ "$spdx_package_count" == <-> && "$spdx_package_count" -gt 0 ]] \
    || fail "runtime SBOM contains no packages"
[[ -s "$runtime_root/ThirdPartyNotices/LICENSES.txt" ]] \
    || fail "runtime license inventory is empty"
[[ -n "$(/usr/bin/find "$runtime_root/ThirdPartyNotices/licenses" -type f -print -quit)" ]] \
    || fail "runtime license-text directory is empty"

while IFS= read -r link; do
    resolved="$(/usr/bin/realpath "$link")" || fail "runtime symlink cannot be resolved: $link"
    case "$resolved" in
        "$runtime_root"/*) ;;
        *) fail "runtime symlink escapes its architecture root: $link" ;;
    esac
done < <(/usr/bin/find "$runtime_root" -type l -print)

temporary_root="$(/usr/bin/mktemp -d /private/tmp/mopelium-runtime-validation.XXXXXX)"
/bin/chmod 0700 "$temporary_root"
actual_paths="$temporary_root/actual-paths.txt"
inventory_paths="$temporary_root/inventory-paths.txt"
(
    cd "$runtime_root"
    /usr/bin/find . -type f ! -path './SHA256SUMS.txt' -print | LC_ALL=C /usr/bin/sort > "$actual_paths"
)

: > "$inventory_paths"
while IFS= read -r line; do
    [[ "$line" =~ '^[0-9a-f]{64}  \./[^/].*$' ]] \
        || fail "runtime inventory contains a malformed entry"
    relative_path="${line[67,-1]}"
    [[ "$relative_path" != *$'\n'* && "$relative_path" != *$'\r'* ]] \
        || fail "runtime inventory contains an unsafe filename"
    print -r -- "$relative_path" >> "$inventory_paths"
done < "$inventory"
LC_ALL=C /usr/bin/sort -u -o "$inventory_paths" "$inventory_paths"
/usr/bin/cmp -s "$actual_paths" "$inventory_paths" \
    || fail "runtime SHA-256 inventory is incomplete or lists unknown files"
(
    cd "$runtime_root"
    /usr/bin/shasum -a 256 --check SHA256SUMS.txt >/dev/null
) || fail "runtime SHA-256 inventory verification failed"

expected_model_paths=$'./config.json\n./model.safetensors\n./preprocessor_config.json'
actual_model_paths="$(
    cd "$runtime_root/models/docling/docling-project--docling-layout-heron"
    /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort
)"
[[ "$actual_model_paths" == "$expected_model_paths" ]] \
    || fail "Docling layout model directory does not match the fixed release set"
[[ -z "$(/usr/bin/find \
    "$runtime_root/models/docling/docling-project--docling-layout-heron" \
    -type l -print -quit)" ]] \
    || fail "Docling layout model directory must not contain symlinks"

expected_tessdata_paths=$'./chi_sim.traineddata\n./chi_tra.traineddata\n./deu.traineddata\n./eng.traineddata\n./fra.traineddata\n./ita.traineddata\n./jpn.traineddata\n./kor.traineddata\n./osd.traineddata\n./por.traineddata\n./spa.traineddata'
actual_tessdata_paths="$(
    cd "$runtime_root/share/tessdata"
    /usr/bin/find . -type f -print | LC_ALL=C /usr/bin/sort
)"
[[ "$actual_tessdata_paths" == "$expected_tessdata_paths" ]] \
    || fail "Tesseract data directory does not match the fixed allowlist"
[[ -z "$(/usr/bin/find "$runtime_root/share/tessdata" -type l -print -quit)" ]] \
    || fail "Tesseract data directory must not contain symlinks"

repository_epubcheck_wrapper="$project_root/Packages/MopeliumTools/Runtime/epubcheck-wrapper/mopelium-epubcheck"
[[ -f "$repository_epubcheck_wrapper" && ! -L "$repository_epubcheck_wrapper" ]] \
    || fail "repository EPUBCheck wrapper is missing or unsafe"
repository_wrapper_digest="$(
    /usr/bin/shasum -a 256 "$repository_epubcheck_wrapper" | /usr/bin/awk '{print $1}'
)"
[[ "$repository_wrapper_digest" == "$(json_value "$spec" artifact_sha256.epubcheck_wrapper)" ]] \
    || fail "repository EPUBCheck wrapper does not match the release spec"

artifact_checks=(
    'artifact_sha256.epubcheck_wrapper|bin/mopelium-epubcheck'
    'artifact_sha256.docling_layout_model.config_json|models/docling/docling-project--docling-layout-heron/config.json'
    'artifact_sha256.docling_layout_model.model_safetensors|models/docling/docling-project--docling-layout-heron/model.safetensors'
    'artifact_sha256.docling_layout_model.preprocessor_config_json|models/docling/docling-project--docling-layout-heron/preprocessor_config.json'
    'artifact_sha256.tessdata.eng|share/tessdata/eng.traineddata'
    'artifact_sha256.tessdata.chi_sim|share/tessdata/chi_sim.traineddata'
    'artifact_sha256.tessdata.chi_tra|share/tessdata/chi_tra.traineddata'
    'artifact_sha256.tessdata.jpn|share/tessdata/jpn.traineddata'
    'artifact_sha256.tessdata.kor|share/tessdata/kor.traineddata'
    'artifact_sha256.tessdata.fra|share/tessdata/fra.traineddata'
    'artifact_sha256.tessdata.deu|share/tessdata/deu.traineddata'
    'artifact_sha256.tessdata.spa|share/tessdata/spa.traineddata'
    'artifact_sha256.tessdata.ita|share/tessdata/ita.traineddata'
    'artifact_sha256.tessdata.por|share/tessdata/por.traineddata'
    'artifact_sha256.tessdata.osd|share/tessdata/osd.traineddata'
)
for artifact_check in $artifact_checks; do
    spec_key="${artifact_check%%|*}"
    relative_path="${artifact_check#*|}"
    expected_digest="$(json_value "$spec" "$spec_key")"
    actual_digest="$(/usr/bin/shasum -a 256 "$runtime_root/$relative_path" | /usr/bin/awk '{print $1}')"
    [[ "$actual_digest" == "$expected_digest" ]] \
        || fail "runtime artifact digest does not match the release spec: $relative_path"
done

while IFS= read -r candidate; do
    file_description="$(/usr/bin/file -b "$candidate")"
    [[ "$file_description" == *"Mach-O"* ]] || continue
    architectures="$(/usr/bin/lipo -archs "$candidate")" \
        || fail "could not inspect Mach-O architecture: $candidate"
    [[ " $architectures " == *" $expected_architecture "* ]] \
        || fail "Mach-O file is missing $expected_architecture: $candidate"
    linked_libraries="$(/usr/bin/otool -L "$candidate")" \
        || fail "could not inspect Mach-O dependencies: $candidate"
    while IFS= read -r dependency; do
        [[ -n "$dependency" ]] || continue
        case "$dependency" in
            /System/Library/*|/usr/lib/*|@loader_path/*|@executable_path/*|@rpath/*)
                ;;
            *)
                fail "Mach-O has a non-system, non-bundle-relative dependency: $candidate -> $dependency"
                ;;
        esac
    done < <(print -r -- "$linked_libraries" | /usr/bin/awk 'NR > 1 { print $1 }')
    load_commands="$(/usr/bin/otool -l "$candidate")" \
        || fail "could not inspect Mach-O load commands: $candidate"
    while IFS= read -r runtime_search_path; do
        [[ -n "$runtime_search_path" ]] || continue
        case "$runtime_search_path" in
            /System/Library/*|/usr/lib/*|@loader_path/*|@executable_path/*)
                ;;
            *)
                fail "Mach-O has a non-system, non-bundle-relative LC_RPATH: $candidate -> $runtime_search_path"
                ;;
        esac
    done < <(print -r -- "$load_commands" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_RPATH" { awaiting_path = 1; next }
        awaiting_path && $1 == "path" { print $2; awaiting_path = 0 }
    ')
    if [[ -n "$expected_signing_identity" ]]; then
        /usr/bin/codesign --verify --strict "$candidate" >/dev/null 2>&1 \
            || fail "runtime Mach-O has no valid strict signature: $candidate"
        signature_info="$(/usr/bin/codesign -dv --verbose=4 "$candidate" 2>&1)"
        [[ "$signature_info" == *"Authority=$expected_signing_identity"* ]] \
            || fail "runtime Mach-O is not signed by the selected Developer ID identity: $candidate"
    fi
done < <(/usr/bin/find "$runtime_root" -type f -print)

if [[ "$validation_mode" == "execute" ]]; then
    [[ -n "$expected_signing_identity" ]] \
        || fail "execute validation requires an exact Developer ID identity"
    sealed_app="$(cd "$runtime_root/../../../.." && pwd -P)"
    [[ "$sealed_app" == *.app \
        && "$runtime_root" == "$sealed_app/Contents/Resources/DocumentRuntime/$expected_architecture" ]] \
        || fail "execute validation is allowed only for a runtime sealed inside its final App"
    /usr/bin/codesign --verify --deep --strict "$sealed_app" >/dev/null 2>&1 \
        || fail "execute validation requires a valid outer App resource seal"
    sealed_app_signature="$(/usr/bin/codesign -dv --verbose=4 "$sealed_app" 2>&1)"
    [[ "$sealed_app_signature" == *"Authority=$expected_signing_identity"* ]] \
        || fail "outer App is not signed by the selected Developer ID identity"

    /bin/mkdir -p "$temporary_root/home" "$temporary_root/tmp"
    /bin/chmod 0700 "$temporary_root/home" "$temporary_root/tmp"

    run_for_architecture() {
        /usr/bin/env -i \
            HOME="$temporary_root/home" \
            TMPDIR="$temporary_root/tmp/" \
            PATH=/usr/bin:/bin \
            LANG=C \
            LC_ALL=C \
            /usr/bin/arch -"$expected_architecture" "$@"
    }

    expected_python_versions=$'python=3.11.9\ndocling=2.117.0\ndocling-slim=2.117.0\ndocling-core=2.89.0\ndocling-parse=7.8.1\npython-docx=1.2.0\npython-pptx=1.0.2\nopenpyxl=3.1.5\nlxml=6.1.1\npypdfium2=5.12.1'
    actual_python_versions="$(
        run_for_architecture "$runtime_root/bin/python3" -I -B -c \
            'import importlib.metadata as m, platform; names=["docling","docling-slim","docling-core","docling-parse","python-docx","python-pptx","openpyxl","lxml","pypdfium2"]; print("python="+platform.python_version()); [print(name+"="+m.version(name)) for name in names]'
    )" || fail "runtime Python dependency inspection failed"
    [[ "$actual_python_versions" == "$expected_python_versions" ]] \
        || fail "runtime Python dependency versions do not match the release spec"

    tesseract_version="$(run_for_architecture "$runtime_root/bin/tesseract" --version 2>&1)" \
        || fail "runtime Tesseract version inspection failed"
    [[ "${tesseract_version%%$'\n'*}" == "tesseract 5.5.3" ]] \
        || fail "runtime Tesseract version does not match the release spec"

    pdfcpu_version="$(
        run_for_architecture "$runtime_root/bin/pdfcpu" --conf disable version 2>&1
    )" || fail "runtime pdfcpu version inspection failed"
    [[ "$pdfcpu_version" == *$'version: 0.13.0'* ]] \
        || fail "runtime pdfcpu version does not match the release spec"

    java_version="$(
        run_for_architecture \
            "$runtime_root/jre/temurin-21.0.11+10/Contents/Home/bin/java" \
            -version 2>&1
    )" || fail "runtime Java version inspection failed"
    [[ "$java_version" == *'openjdk version "21.0.11"'* \
        && "$java_version" == *'Temurin-21.0.11+10'* ]] \
        || fail "runtime Temurin JRE version does not match the release spec"

    epubcheck_version="$(
        run_for_architecture "$runtime_root/bin/mopelium-epubcheck" --version 2>&1
    )" || fail "runtime EPUBCheck version inspection failed"
    [[ "$epubcheck_version" == *'5.3.0'* ]] \
        || fail "runtime EPUBCheck version does not match the release spec"

    libreoffice_version="$(
        run_for_architecture \
            "$runtime_root/libreoffice/26.8.0.0.beta1/LibreOffice.app/Contents/MacOS/soffice" \
            --version 2>&1
    )" || fail "runtime LibreOffice version inspection failed"
    [[ "${libreoffice_version%%$'\n'*}" == 'LibreOfficeDev 26.8.0.0.beta1'* ]] \
        || fail "runtime LibreOffice version does not match the release spec"
fi

print -- "Validated document runtime $expected_architecture ($validation_mode) at $runtime_root"
