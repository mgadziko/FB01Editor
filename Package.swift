// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FB01Editor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FB01Editor",
            targets: ["FB01Editor"]
        ),
        .executable(
            name: "fb01-dump",
            targets: ["fb01-dump"]
        ),
        .executable(
            name: "fb01-gm-load",
            targets: ["fb01-gm-load"]
        ),
        .executable(
            name: "FB01EditorApp",
            targets: ["FB01EditorApp"]
        ),
    ],
    targets: [
        .target(
            name: "FB01Editor"
        ),
        .executableTarget(
            name: "fb01-dump",
            dependencies: ["FB01Editor"]
        ),
        .executableTarget(
            name: "fb01-gm-load",
            dependencies: ["FB01Editor"]
        ),
        .executableTarget(
            name: "FB01EditorApp",
            dependencies: ["FB01Editor"]
        ),
        .testTarget(
            name: "FB01EditorTests",
            dependencies: ["FB01Editor", "FB01EditorApp"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
