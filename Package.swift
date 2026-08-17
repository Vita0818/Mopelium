// swift-tools-version:5.9
import PackageDescription

// Mopelium root SwiftPM manifest. Product versioning is owned by project.yml;
// package comments below that mention early v0.x milestones describe when a
// subsystem was introduced, not the current product version. See
// docs/VERSIONING.md.

let package = Package(
    name: "Mopelium",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "MopeliumCore", targets: ["MopeliumCore"]),
        .library(name: "MopeliumProtocol", targets: ["MopeliumProtocol"]),
        .library(name: "MopeliumProviders", targets: ["MopeliumProviders"]),
        .library(name: "MopeliumArtifacts", targets: ["MopeliumArtifacts"]),
        .library(name: "MopeliumConversation", targets: ["MopeliumConversation"]),
        .library(name: "MopeliumTools", targets: ["MopeliumTools"]),
        .library(name: "MopeliumKnowledge", targets: ["MopeliumKnowledge"]),
        .library(name: "MopeliumSkills", targets: ["MopeliumSkills"]),
        .library(name: "MopeliumPermission", targets: ["MopeliumPermission"]),
        .library(name: "MopeliumMCP", targets: ["MopeliumMCP"]),
        .library(name: "MopeliumMCPStdio", targets: ["MopeliumMCPStdio"]),
        .library(name: "MopeliumAgentKernel", targets: ["MopeliumAgentKernel"]),
        .library(name: "MopeliumCowork", targets: ["MopeliumCowork"]),
        .library(name: "MopeliumMultimodal", targets: ["MopeliumMultimodal"]),
        .library(name: "MopeliumSharedUI", targets: ["MopeliumSharedUI"]),
        // The CLI IS a SwiftPM executable (no Xcode needed): `swift run mopelium chat`.
        .executable(name: "mopelium", targets: ["MopeliumCLI"]),
        // The MopeliumMac GUI app is an Xcode App target, not an SPM product.
        // SwiftPM cannot build the .app bundle. See project.yml + README.
    ],
    dependencies: [
        // Audited in-tree thin derivative of Microsoft SwiftStreamingMarkdown
        // v0.6.0. Provenance and local patches live beside the vendored source.
        .package(path: "Vendor/SwiftStreamingMarkdown"),
        // Audited client-only derivative of the official Model Context
        // Protocol Swift SDK 0.12.1 at a0ae212e. Its upstream identity,
        // exclusions, licenses, and patch ledger live beside the source.
        .package(path: "Vendor/MCPClientSDK"),
        // Official portable CryptoKit-compatible backend for Linux CLI builds.
        // Exact release provenance and license inventory are recorded in
        // ThirdPartyNotices/SwiftCrypto.md.
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            exact: "4.5.1"
        ),
        // Safe YAML parser for bounded OKF frontmatter in the knowledge target.
        // Exact commit/license provenance is recorded in
        // ThirdPartyNotices/KnowledgeRetrieval.md.
        .package(
            url: "https://github.com/jpsim/Yams.git",
            exact: "6.2.2"
        ),
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
            dependencies: [
                "MopeliumCore", "MopeliumProtocol",
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
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
            // (still tool-free — see ARCHITECTURE.md §3.4 / §4).
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
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumPTYLauncher",
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumTools/Sources"
        ),
        // OKF/Profile snapshots, deterministic validation, local embedding,
        // derived indexes, and the snapshot-bound search_knowledge tool.
        .target(
            name: "MopeliumKnowledge",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumTools",
                "MopeliumProviders", "MopeliumPermission",
                .product(name: "Yams", package: "Yams"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumKnowledge",
            exclude: ["Tests"],
            sources: ["Sources"],
            resources: [
                .copy("Resources/Schemas"),
            ]
        ),
        .target(
            name: "MopeliumSkills",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumTools",
                "MopeliumPermission",
            ],
            path: "Packages/MopeliumSkills",
            exclude: ["Tests"],
            sources: ["Sources"],
            resources: [
                .copy("Resources/BundledSkills"),
            ]
        ),
        .target(
            name: "MopeliumPermission",
            // Providers added in v0.3 for the model-backed reviewer (layer B).
            dependencies: ["MopeliumCore", "MopeliumProtocol", "MopeliumProviders"],
            path: "Packages/MopeliumPermission/Sources"
        ),
        // Production remote MCP HTTP/OAuth requests use libcurl's
        // CURLOPT_RESOLVE socket binding on macOS and Linux.
        .target(
            name: "MopeliumCurlTransport",
            path: "Packages/MopeliumCurlTransport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("curl"),
            ]
        ),
        // External MCP Server client core, including the client-side handlers
        // for callbacks initiated by a connected server. This target contains
        // no MCP Server implementation or server-facing product seam. It has
        // no dependency on Conversation, Providers, AgentKernel, Cowork, or an
        // app target; those layers inject event/artifact/inference services
        // through narrow interfaces.
        .target(
            name: "MopeliumMCP",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumTools",
                .target(
                    name: "MopeliumCurlTransport",
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(name: "MCP", package: "MCPClientSDK"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumMCP/Sources"
        ),
        // Linux-only kernel execution guard support for local MCP stdio.
        // The C shim is inert on Apple platforms; keeping it separate avoids
        // placing fork/ptrace/seccomp code in the portable client core.
        .target(
            name: "MopeliumMCPStdioGuard",
            path: "Packages/MopeliumMCPStdio/ExecutionGuard",
            publicHeadersPath: "include"
        ),
        // Local stdio process ownership is a separate linkage boundary so the
        // portable MCP client core never owns local processes implicitly.
        .target(
            name: "MopeliumMCPStdio",
            dependencies: [
                "MopeliumMCP", "MopeliumMCPStdioGuard",
                "MopeliumCore", "MopeliumProtocol", "MopeliumTools",
                .product(name: "MCP", package: "MCPClientSDK"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumMCPStdio/Sources"
        ),
        .target(
            name: "MopeliumAgentKernel",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation",
                "MopeliumArtifacts", "MopeliumMCP", "MopeliumSkills",
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumAgentKernel/Sources"
        ),
        // v0.3 — Cowork: multi-agent orchestration over a mediated message bus.
        .target(
            name: "MopeliumCowork",
            dependencies: [
                "MopeliumCore", "MopeliumProtocol", "MopeliumProviders", "MopeliumTools",
                "MopeliumPermission", "MopeliumConversation", "MopeliumAgentKernel",
                "MopeliumSkills",
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
                    condition: .when(platforms: [.macOS])
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
                "MopeliumArtifacts", "MopeliumTools", "MopeliumPermission", "MopeliumAgentKernel", "MopeliumCowork",
                "MopeliumMCP", "MopeliumMCPStdio", "MopeliumSkills", "MopeliumKnowledge",
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Apps/mopelium-cli/Sources"
        ),
        // Development-only executable exercised by the pinned official MCP
        // client conformance runner. It is not a shipped product and contains
        // no MCP server implementation or server-facing API.
        .executableTarget(
            name: "MopeliumMCPConformanceClient",
            dependencies: [
                "MopeliumMCP", "MopeliumCore", "MopeliumProtocol",
                .product(name: "MCP", package: "MCPClientSDK"),
            ],
            path: "Packages/MopeliumMCPConformanceClient/Sources"
        ),
        // The MopeliumMac GUI app target is defined in the Xcode project generated
        // from project.yml and links these library products.

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
            name: "MopeliumKnowledgeTests",
            dependencies: [
                "MopeliumKnowledge", "MopeliumCore", "MopeliumProtocol",
                "MopeliumTools",
            ],
            path: "Packages/MopeliumKnowledge/Tests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "MopeliumSkillsTests",
            dependencies: [
                "MopeliumSkills", "MopeliumCore", "MopeliumProtocol", "MopeliumTools",
            ],
            path: "Packages/MopeliumSkills/Tests"
        ),
        .testTarget(
            name: "MopeliumPermissionTests",
            dependencies: ["MopeliumPermission", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders"],
            path: "Packages/MopeliumPermission/Tests"
        ),
        .testTarget(
            name: "MopeliumMCPTests",
            dependencies: [
                "MopeliumMCP", "MopeliumMCPStdio", "MopeliumCore",
                "MopeliumProtocol", "MopeliumTools",
                .product(name: "MCP", package: "MCPClientSDK"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumMCP/Tests"
        ),
        .testTarget(
            name: "MopeliumCLITests",
            dependencies: [
                "MopeliumCLI", "MopeliumAgentKernel",
                "MopeliumConversation", "MopeliumCore",
                "MopeliumMCP", "MopeliumProtocol",
            ],
            path: "Apps/mopelium-cli/Tests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "MopeliumAgentKernelTests",
            dependencies: [
                "MopeliumAgentKernel", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation",
                "MopeliumArtifacts", "MopeliumMCP", "MopeliumSkills", "MopeliumKnowledge",
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ],
            path: "Packages/MopeliumAgentKernel/Tests"
        ),
        .testTarget(
            name: "MopeliumCoworkTests",
            dependencies: [
                "MopeliumCowork", "MopeliumCore", "MopeliumProtocol", "MopeliumProviders",
                "MopeliumTools", "MopeliumPermission", "MopeliumConversation", "MopeliumAgentKernel",
                "MopeliumSkills",
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
