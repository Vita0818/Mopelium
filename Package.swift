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
        .executableTarget(
            name: "MopeliumCLI",
            dependencies: ["MopeliumCore", "MopeliumProviders"],
            path: "Apps/mopelium-cli/Sources"
        ),
        .executableTarget(
            name: "MopeliumMac",
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
    ]
)
