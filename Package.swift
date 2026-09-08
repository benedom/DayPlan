// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayPlan",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DayPlan",
            path: "Sources/DayPlan",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DayPlanTests",
            dependencies: ["DayPlan"],
            path: "Tests/DayPlanTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
