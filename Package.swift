// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KapKap",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "KapKap", targets: ["KapKap"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "KapKap", dependencies: [
            "CaptureCore",
            .product(name: "Sparkle", package: "Sparkle")
        ]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
        .testTarget(name: "RecordingTests", dependencies: ["KapKap"])
    ],
    swiftLanguageModes: [.v5]
)
