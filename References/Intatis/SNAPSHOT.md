# Intatis reference snapshot

This directory is an inert, source-level reference copy of the Intatis working tree. It is not linked from Mopelium's `Package.swift`, `project.yml`, or Xcode project.

## Source

- Source repository: `/Users/vita/Vitemis/Intatis`
- Copied at: 2026-07-26 09:27:00 +08
- Source branch: `main`
- Source HEAD: `437fcb8a962ad8a833cf23eee956c3f92a088a9c`
- Source HEAD subject: `v0.26`
- Snapshot basis: tracked contents from the clean HEAD worktree
- Source status at copy time: clean; 0 tracked or untracked changes

This directory is the explicit 2026-07-26 Intatis reference baseline for subsequent Mopelium work even if Intatis changes later.

## Integration status

The Chat, Code, Cowork, provider, permission, tool, multimodal, SharedUI, CLI, macOS, and iOS implementation baseline from this snapshot has been migrated into Mopelium's active `Apps/`, `Packages/`, `Vendor/`, and build configuration. The active copy uses Mopelium product/module identifiers and an environment-only API-key policy. This reference directory remains inert and is not itself compiled.

## Included

- `Apps/`: 40 files
- `Packages/`: 210 files, including Sources and Tests
- `Vendor/SwiftStreamingMarkdown/`: 116 tracked vendored source, test, license and patch-ledger files
- `ThirdPartyNotices/`: 3 files
- `docs/`: 21 files
- `scripts/`: 2 files
- Root project/context files: 12 files
- Copied source/project files before this metadata file: 404

The copy includes the current tracked project files except the deliberately excluded report directories below. It was produced from a Git archive of the clean source HEAD rather than by recursively copying the worktree.

## Deliberately excluded

- `.git/` and all Git history/locks
- `.build/`, `.swiftpm/`, DerivedData, generated `Intatis.xcodeproj`, and Xcode user state
- `codex-report/`, `claude-report/`, `gemini-report/`, and `cursor-report/`
- `.DS_Store`
- `.intatis/`, browser profiles, cookies, sessions, downloads, and runtime state
- `.env`, auth files, secret files, credentials, keys, certificates, and provisioning profiles
- ignored or otherwise untracked files

These exclusions keep the snapshot non-nested, portable, and free of known build/runtime or credential-bearing paths and filenames. The snapshot is source-complete for the audited project scope, not a byte-for-byte repository clone.

## Verification at copy time

- Expected source/project file list versus copied file list: 0 differences
- Nested `.git` / build cache / runtime-state directories found: 0
- Excluded credential-bearing path/filename patterns found in the snapshot: 0
- Symlink and Git-link entries found: 0
- Copied file content before this metadata file: approximately 6.7 MiB

The copy-time safety check included path/filename checks and a redacted high-confidence token/key-pattern scan. All matches were confined to test fixtures or token-like test identifiers and labels. This narrow check does not claim to prove the absence of every possible secret embedded in otherwise legitimate source text; a comprehensive secret scan remains a separate verification step if that assurance is required.

## Usage rule

Treat this directory as a read-only migration reference. Make customized implementations in Mopelium's normal `Packages/`, `Apps/`, and package-local `Tests/` trees. If a newer Intatis baseline is needed, refresh the snapshot deliberately and update this file rather than silently mixing revisions.
