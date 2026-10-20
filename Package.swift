// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBuddy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacBuddy", targets: ["MacBuddy"])],
    targets: [
        .target(name: "NativeTelemetry", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .systemLibrary(name: "CSQLite"),
        .target(name: "MacBuddyCore", dependencies: ["NativeTelemetry", "CSQLite"]),
        .executableTarget(name: "MacBuddy", dependencies: ["MacBuddyCore"], linkerSettings: [.linkedFramework("Carbon")]),
        .executableTarget(name: "MacBuddyChecks", dependencies: ["MacBuddyCore"], path: "Tests/MacBuddyCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
