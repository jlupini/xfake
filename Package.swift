// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "xfake",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGVirtualDisplayBridge", publicHeadersPath: "include"),
        .target(name: "XFakeCore", dependencies: ["CGVirtualDisplayBridge"]),
        .executableTarget(name: "xfake", dependencies: ["XFakeCore"]),
        .testTarget(name: "XFakeCoreTests", dependencies: ["XFakeCore"]),
    ]
)
