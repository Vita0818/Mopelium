// swift-tools-version:5.9
import PackageDescription

// Mopelium v0.1 — single root manifest.
// One target per module; target dependencies enforce the acyclic DAG from
// ARCHITECTURE.md §2.1. The conceptual `Packages/<Name>` split maps 1:1 to
// these targets and can be promoted to standalone SwiftPM packages later.
//
// Buildable/testable today: Core / Protocol / Providers / Artifacts / Conversation
// (pure Swift, no Apple-only frameworks). SharedUI + MopeliumMac use SwiftUI/AppKit,
// guarded with `#if canImport(SwiftUI)` so the package still builds on Linux.

let package = Package(
    name: "Mopelium",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "MopeliumCore", targets: ["MopeliumCore"]),
        .library(name: "MopeliumProtocol", targets: ["MopeliumProtocol"]),
        .library(name: "MopeliumProviders", targets: ["MopeliumProviders"]),
        .library(name: "MopeliumArtifacts", targets: ["MopeliumArtifacts"]),
        .library(name: "MopeliumConversation", targets: ["MopeliumConversation"]),
        .library(name: "MopeliumTools", targets: ["MopeliumTools"]),
        .library(name: "MopeliumPermission", targets: ["MopeliumPermission"]),
        .library(name: "MopeliumAgentKernel", targets: ["MopeliumAgentKernel"]),
        .library(name: "MopeliumCowork", targets: ["MopeliumCowork"]),
        .library(name: "MopeliumMultimodal", targets: ["MopeliumMultimodal"]),
        .library(name: "MopeliumSharedUI", targets: ["MopeliumSharedUI"]),
        // The CLI IS a SwiftPM executable (no Xcode needed): `swift run mopelium chat`.
        .executable(name: "mopelium", targets: ["MopeliumCLI"]),
        // The GUI apps (MopeliumMac, MopeliumiOS) are Xcode App targets, not SPM
        // products — SwiftPM cannot build a .app bundle, and iOS apps cannot be
        // built from SPM at all. See project.yml (XcodeGen) + README.
    ],
    dependencies: [
        // Audited in-tree thin derivative of Microsoft SwiftStreamingMarkdown
        // v0.6.0. Provenance and local patches live beside the vendored source.
        .package(path: "Vendor/SwiftStreamingMarkdown"),
    ],
    targets: [
        // MARK: Library targets (module == target)
        .target(
            name: "MopeliumCore",
            path: "Packages/MopeliumCore/Sources"
        ),
        .target(
            name: "MopeliumProtocol",
            dependencies: ["MopeliumCore"],
            path: "Packages/MopeliumProtocol/Sources"
        ),
        .target(
            name: "MopeliumProviders",
            dependencies: ["MopeliumCore", "MopeliumProtocol"],
            path: "Packages/MopeliumProviders/Sources"
        ),
        .target(
            name: "MopeliumArtifacts",
            dependencies: ["MopeliumCore", "MopeliumProtocol"],
            path: "Packages/MopeliumArtifacts/Sources"
        ),
        .target(
            name: "MopeliumConversation",
            // ChatLoop drives a ChatProvider, so Conversation depends on Providers
            // (still tool-free — see ARCHITECTURE.md §3.4 / §4: iOS links this, not the kernel).
            dependencies: ["MopeliumCore", "MopeliumProtocol", "MopeliumProviders", "MopeliumArtifacts"],
            path: "Packages/MopeliumConversation/Sources"
        ),
        // v0.2 — Code: tools, deterministic permission gate, single-agent kernel.
        .target(
            name: "MopeliumPTYLauncher",
            path: "Packages/MopeliumPTYLauncher",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MopeliumTools",
            dependencies: ["MopeliumCore", "MopeliumProtocol", "MopeliumPTYLauncher"],
            path: "Packages/MopeliumTools/Sources"
        ),
        .target(
            name: "MopeliumPermission",
            // Providers added in v0.3 for the model-backed reviewer (layer B).
            dependencies: ["MopeliumCore", "MopeliumProtocol", "MopeliumProviders"],
            path: "Packages/MopeliumPermission/Sources"
        ),
        .target(
            name: "MopeliumAgentKernel",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation", "MopeliumArtifacts",
            ],
            path: "Packages/MopeliumAgentKernel/Sources"
        ),
        // v0.3 — Cowork: multi-agent orchestration over a mediated message bus.
        .target(
            name: "MopeliumCowork",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders", "MopeliumTools",
                "MopeliumPermission", "MopeliumConversation", "MopeliumAgentKernel",
            ],
            path: "Packages/MopeliumCowork/Sources"
        ),
        // v0.4 — Multimodal: image/video generation + transcription → artifacts.
        .target(
            name: "MopeliumMultimodal",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumArtifacts", "MopeliumConversation",
            ],
            path: "Packages/MopeliumMultimodal/Sources"
        ),
        .target(
            name: "MopeliumSharedUI",
            // Providers is needed because ChatViewModel drives ProviderRegistry.
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumConversation", "MopeliumArtifacts",
                .product(
                    name: "SwiftStreamingMarkdown",
                    package: "SwiftStreamingMarkdown",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
            ],
            path: "Packages/MopeliumSharedUI/Sources"
        ),
        // v0.6 — CLI: Swift-native `mopelium` command (chat + code agent), talks to
        // any OpenAI-compatible endpoint via env vars.
        .executableTarget(
            name: "MopeliumCLI",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders", "MopeliumConversation",
                "MopeliumTools", "MopeliumPermission", "MopeliumAgentKernel", "MopeliumCowork",
            ],
            path: "Apps/mopelium-cli/Sources"
        ),
        // GUI app targets (MopeliumMac macOS app, MopeliumiOS iOS app) are defined in
        // the Xcode project generated from project.yml — they link these library
        // products. The iOS app intentionally links only the subset.

        // MARK: Test targets (none depend on app targets; SharedUI tests run headlessly on macOS)
        .testTarget(
            name: "MopeliumCoreTests",
            dependencies: ["MopeliumCore"],
            path: "Packages/MopeliumCore/Tests"
        ),
        .testTarget(
            name: "MopeliumProtocolTests",
            dependencies: ["MopeliumProtocol", "MopeliumCore"],
            path: "Packages/MopeliumProtocol/Tests"
        ),
        .testTarget(
            name: "MopeliumProvidersTests",
            dependencies: ["MopeliumProviders", "MopeliumCore", "MopeliumProtocol"],
            path: "Packages/MopeliumProviders/Tests"
        ),
        .testTarget(
            name: "MopeliumArtifactsTests",
            dependencies: ["MopeliumArtifacts", "MopeliumCore"],
            path: "Packages/MopeliumArtifacts/Tests"
        ),
        .testTarget(
            name: "MopeliumConversationTests",
            dependencies: ["MopeliumConversation", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders"],
            path: "Packages/MopeliumConversation/Tests"
        ),
        .testTarget(
            name: "MopeliumToolsTests",
            dependencies: ["MopeliumTools", "MopeliumCore"],
            path: "Packages/MopeliumTools/Tests"
        ),
        .testTarget(
            name: "MopeliumPermissionTests",
            dependencies: ["MopeliumPermission", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders"],
            path: "Packages/MopeliumPermission/Tests"
        ),
        .testTarget(
            name: "MopeliumAgentKernelTests",
            dependencies: [
                "MopeliumAgentKernel", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation",
            ],
            path: "Packages/MopeliumAgentKernel/Tests"
        ),
        .testTarget(
            name: "MopeliumCoworkTests",
            dependencies: [
                "MopeliumCowork", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation", "MopeliumAgentKernel",
            ],
            path: "Packages/MopeliumCowork/Tests"
        ),
        .testTarget(
            name: "MopeliumMultimodalTests",
            dependencies: [
                "MopeliumMultimodal", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumArtifacts", "MopeliumConversation",
            ],
            path: "Packages/MopeliumMultimodal/Tests"
        ),
        .testTarget(
            name: "MopeliumSharedUITests",
            dependencies: ["MopeliumSharedUI"],
            path: "Packages/MopeliumSharedUI/Tests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
