// swift-tools-version:5.9
//
// Phase 1 placeholder. URL and checksum are placeholders; the release
// pipeline will populate them at tag-push time. Do not consume this
// manifest until v1.0 ships.

import PackageDescription

let package = Package(
    name: "LYNX",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LYNX", targets: ["LYNX"])
    ],
    targets: [
        .binaryTarget(
            name: "LYNX",
            url: "https://github.com/Syneticai/lynx/releases/download/v0.0.0-placeholder/LYNX.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    ]
)
