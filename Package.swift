// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FB01Editor",
    products: [
        .library(
            name: "FB01Editor",
            targets: ["FB01Editor"]
        ),
    ],
    targets: [
        .target(
            name: "FB01Editor"
        ),
        .testTarget(
            name: "FB01EditorTests",
            dependencies: ["FB01Editor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
