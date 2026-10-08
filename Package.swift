// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HMJESeed",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SeedCore", path: "Sources/SeedCore"),
        .executableTarget(name: "hmje-seed", dependencies: ["SeedCore"], path: "Sources/hmje-seed"),
    ]
)
