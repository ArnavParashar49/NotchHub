// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchHubCore", targets: ["NotchHubCore"]),
        .library(name: "NotchHubSystem", targets: ["NotchHubSystem"]),
        .executable(name: "NotchHub", targets: ["NotchHub"]),
    ],
    targets: [
        // Pure, testable domain: geometry, activity model, queue, spring, tokens.
        .target(
            name: "NotchHubCore",
            path: "Sources/NotchHubCore"
        ),
        // System listeners: native sources of truth (battery, volume, brightness,
        // now-playing, downloads, timers, system events). No UI, no activity state.
        .target(
            name: "NotchHubSystem",
            dependencies: ["NotchHubCore"],
            path: "Sources/NotchHubSystem"
        ),
        // The app: window chrome + SwiftUI island. Reads activity state only.
        .executableTarget(
            name: "NotchHub",
            dependencies: ["NotchHubCore", "NotchHubSystem"],
            path: "Sources/NotchHub"
        ),
        // Run with ./scripts/test.sh — see the note there about Command Line Tools.
        .testTarget(
            name: "NotchHubCoreTests",
            dependencies: ["NotchHubCore"],
            path: "Tests/NotchHubCoreTests"
        ),
        .testTarget(
            name: "NotchHubSystemTests",
            dependencies: ["NotchHubCore", "NotchHubSystem"],
            path: "Tests/NotchHubSystemTests"
        ),
    ]
)
