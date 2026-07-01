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
            exclude: [
                "Info.plist",
                "AIUsageMonitor.entitlements",
                "AppIcon.icns"
            ],
            resources: [
                .copy("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "AIUsageMonitorTests",
            dependencies: ["AIUsageMonitor"],
            path: "Tests/AIUsageMonitorTests"
        )
    ]
)
