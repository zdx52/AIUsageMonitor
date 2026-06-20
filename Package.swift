// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AIUsageMonitor",
            path: "AIUsageMonitor",
            resources: [
                .copy("Assets.xcassets")
            ]
        )
    ]
)
