// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipFormatShared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipFormatShared", targets: ["ClipFormatShared"])
    ],
    targets: [
        .target(name: "ClipFormatShared"),
        .testTarget(name: "ClipFormatSharedTests", dependencies: ["ClipFormatShared"])
    ]
)
