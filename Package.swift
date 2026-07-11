// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mopelium",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "MopeliumCore", targets: ["MopeliumCore"]),
        .library(name: "MopeliumProviders", targets: ["MopeliumProviders"]),
        .library(name: "MopeliumTools", targets: ["MopeliumTools"]),
        .library(name: "MopeliumAgent", targets: ["MopeliumAgent"]),
        .executable(name: "mopelium", targets: ["MopeliumCLI"]),
        .executable(name: "MopeliumMac", targets: ["MopeliumMac"]),
    ],
    targets: [
        .target(
            name: "MopeliumCore",
            path: "Packages/MopeliumCore/Sources"
        ),
        .target(
            name: "MopeliumProviders",
            dependencies: ["MopeliumCore"],
            path: "Packages/MopeliumProviders/Sources"
        ),
        .target(
            name: "MopeliumTools",
            path: "Packages/MopeliumTools/Sources"
        ),
        .target(
            name: "MopeliumAgent",
            dependencies: ["MopeliumCore", "MopeliumProviders", "MopeliumTools"],
            path: "Packages/MopeliumAgent/Sources"
        ),
        .executableTarget(
            name: "MopeliumCLI",
            dependencies: ["MopeliumCore", "MopeliumProviders", "MopeliumTools", "MopeliumAgent"],
            path: "Apps/mopelium-cli/Sources"
        ),
        .executableTarget(
            name: "MopeliumMac",
            dependencies: ["MopeliumCore", "MopeliumProviders", "MopeliumTools", "MopeliumAgent"],
            path: "Apps/MopeliumMac/Sources"
        ),
        .testTarget(
            name: "MopeliumCoreTests",
            dependencies: ["MopeliumCore"],
            path: "Tests/MopeliumCoreTests"
        ),
        .testTarget(
            name: "MopeliumProvidersTests",
            dependencies: ["MopeliumProviders"],
            path: "Tests/MopeliumProvidersTests"
        ),
        .testTarget(
            name: "MopeliumToolsTests",
            dependencies: ["MopeliumTools"],
            path: "Tests/MopeliumToolsTests"
        ),
        .testTarget(
            name: "MopeliumAgentTests",
            dependencies: ["MopeliumAgent", "MopeliumProviders"],
            path: "Tests/MopeliumAgentTests"
        ),
    ]
)
