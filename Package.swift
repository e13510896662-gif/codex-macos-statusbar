// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexFlow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexFlow", targets: ["CodexFlow"])],
    targets: [
        .target(name: "FlowCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "CodexFlow", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])
    ]
)
