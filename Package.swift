// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIConsumeStatusBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TokenUsageCore"),
        .target(name: "TokenUsageData", dependencies: ["TokenUsageCore"]),
        .executableTarget(
            name: "AIConsumeStatusBar",
            dependencies: ["TokenUsageCore", "TokenUsageData"]
        ),
        .testTarget(
            name: "TokenUsageCoreTests",
            dependencies: ["TokenUsageCore"],
            path: "tests/unit/TokenUsageCoreTests"
        ),
        .testTarget(
            name: "TokenUsageDataTests",
            dependencies: ["TokenUsageData", "TokenUsageCore"],
            path: "tests/unit/TokenUsageDataTests"
        ),
        .testTarget(
            name: "Acceptance_req_20261015_macos_status_bar_token_usage",
            dependencies: ["TokenUsageCore", "TokenUsageData"],
            path: "tests/req-20261015-macos-status-bar-token-usage"
        ),
    ],
    swiftLanguageModes: [.v6]
)
