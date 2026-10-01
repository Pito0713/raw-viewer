// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RawViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RawViewerCore"),
        .executableTarget(name: "RawViewer", dependencies: ["RawViewerCore"]),
        .testTarget(name: "RawViewerCoreTests", dependencies: ["RawViewerCore"]),
    ]
)
