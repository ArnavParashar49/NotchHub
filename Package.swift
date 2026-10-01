// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NotchHubOrbs", targets: ["NotchHubOrbs"]),
        .library(name: "NotchHubCore", targets: ["NotchHubCore"]),
        .library(name: "NotchHubSystem", targets: ["NotchHubSystem"]),
        .executable(name: "NotchHub", targets: ["NotchHub"]),
    ],
    targets: [
        // NEO's thinking orbs: a port of the thinking-orbs geometry engine (MIT,
        // see THIRD_PARTY.md) and the SwiftUI canvas that paints it.
        .target(
            name: "NotchHubOrbs",
            path: "Sources/NotchHubOrbs"
        ),
        // Pure, testable domain: geometry, activity model, queue, spring, tokens.
        .target(
            name: "NotchHubCore",
            dependencies: ["NotchHubOrbs"],
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
            dependencies: ["NotchHubOrbs", "NotchHubCore", "NotchHubSystem"],
            path: "Sources/NotchHub"
        ),
        // Run with ./scripts/test.sh — see the note there about Command Line Tools.
        .testTarget(
            name: "NotchHubOrbsTests",
            dependencies: ["NotchHubOrbs"],
            path: "Tests/NotchHubOrbsTests",
            // Frames dumped from the JS engine, read by path (not a bundle).
            exclude: ["Goldens"]
        ),
        .testTarget(
            name: "NotchHubCoreTests",
            dependencies: ["NotchHubCore"],
            path: "Tests/NotchHubCoreTests"
        ),
        .testTarget(
            name: "NotchHubSystemTests",
            dependencies: ["NotchHubCore", "NotchHubSystem"],
            path: "Tests/NotchHubSystemTests",
            // The stub NEO core the listener tests run against.
            exclude: ["Fixtures"]
        ),
    ]
)
