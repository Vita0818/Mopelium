#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"

fail() {
    print -u2 -- "error: $*"
    exit 1
}

[[ "$(/usr/bin/awk '/^name:/ { print $2; exit }' "$project_root/project.yml")" == "Mopelium" ]] \
    || fail "project.yml does not declare the Mopelium project"
/usr/bin/grep -Fq -- "PRODUCT_BUNDLE_IDENTIFIER: com.Vita0818.Mopelium" \
    "$project_root/project.yml" \
    || fail "project.yml does not declare the canonical Mopelium Bundle ID"

for removed in \
    "$project_root/Apps/IntatisiOS" \
    "$project_root/Apps/MopeliumiOS" \
    "$project_root/Apps/MopeliumMac/MopeliumMac.AppStore.entitlements"
do
    [[ ! -e "$removed" && ! -L "$removed" ]] \
        || fail "removed product identity is still present: $removed"
done

if /usr/bin/grep -Eq -- \
    'MopeliumMacAppStore:|MopeliumiOS:|MOPELIUM_MAC_APP_STORE' \
    "$project_root/project.yml"; then
    fail "project.yml still contains a deleted App target or compile condition"
fi

named_paths="$(
    /usr/bin/find \
        "$project_root/Apps" \
        "$project_root/Packages" \
        "$project_root/.agents/skills" \
        "$project_root/Vendor/SwiftStreamingMarkdown" \
        -depth \( -name '*Intatis*' -o -name '*intatis*' -o -name '*INTATIS*' \) \
        -print
)"
[[ -z "$named_paths" ]] \
    || fail "active source paths still contain predecessor identity:\n$named_paths"

allowed_legacy_files='^(.gitignore|scripts/check-mopelium-identity\.sh|scripts/package-macos-release\.sh|Apps/MopeliumMac/Sources/(AppConfig|Keychain)\.swift|Apps/mopelium-cli/Sources/(CLIConfig|CLIProviderCatalog)\.swift|Apps/mopelium-cli/Tests/CLIConfigRuntimeBudgetTests\.swift|Packages/MopeliumCore/(Sources/ProductIdentity|Tests/ProductIdentityMigrationTests)\.swift|Packages/MopeliumProtocol/(Sources/Leases|Tests/WorkspaceLeaseTests)\.swift|Packages/MopeliumProviders/(Sources/ProviderRequestAdapter|Tests/MopeliumProvidersTests)\.swift|Packages/MopeliumPermission/(Sources/SecretScanner|Tests/MopeliumPermissionTests)\.swift|Packages/MopeliumTools/Sources/ShellGit\.swift)$'

legacy_files="$(
    cd "$project_root"
    rg -l 'Intatis|intatis|INTATIS' \
        Apps Packages scripts Package.swift project.yml Makefile .gitignore \
        || true
)"
unexpected="$(
    print -r -- "$legacy_files" \
        | /usr/bin/grep -Ev -- "$allowed_legacy_files" \
        || true
)"
[[ -z "$unexpected" ]] \
    || fail "unexpected predecessor identity remains in active code:\n$unexpected"

/usr/bin/grep -Fq -- 'registryVersion: "mopelium.standard.v8"' \
    "$project_root/Packages/MopeliumTools/Sources/ToolProtocol.swift" \
    || fail "standard registry is not Mopelium v8"
/usr/bin/grep -Fq -- 'registryVersion: "mopelium.cowork.v8"' \
    "$project_root/Packages/MopeliumCowork/Sources/Orchestrator.swift" \
    || fail "Cowork registry is not Mopelium v8"
/usr/bin/grep -Fq -- '"__mopelium_authorization_context"' \
    "$project_root/Packages/MopeliumAgentKernel/Sources/AuthorizationSidecar.swift" \
    || fail "automatic permission sidecar is not canonical Mopelium"

print -- "Mopelium active identity check passed"
