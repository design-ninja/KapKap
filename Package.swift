// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KapKap",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "KapKap", targets: ["KapKap"])],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "KapKap", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
        .testTarget(name: "RecordingTests", dependencies: ["KapKap"])
    ],
    swiftLanguageModes: [.v5]
)
