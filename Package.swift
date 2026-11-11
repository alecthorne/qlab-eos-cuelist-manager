// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QLabEosCuelistManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QLabEosCuelistManager", targets: ["QLabEosCuelistManager"]),
        .library(name: "CueSyncCore", targets: ["CueSyncCore"]),
    ],
    targets: [
        // Platform-independent logic: OSC encoding, TCP framing, and parsing of
        // QLab and Eos replies. Foundation only, so it is easy to unit test.
        .target(name: "CueSyncCore"),
        // The macOS SwiftUI app: settings, networking (Network.framework) and UI.
        .executableTarget(
            name: "QLabEosCuelistManager",
            dependencies: ["CueSyncCore"],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "CueSyncCoreTests",
            dependencies: ["CueSyncCore"]
        ),
    ]
)
