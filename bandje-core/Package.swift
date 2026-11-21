// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-only
import PackageDescription

// BandjeKit: code shared by Bandje for macOS (../bandje-mac) and for iOS (../bandje-ios).
// No dependencies and no networking code (scripts/check-no-network.sh).
let package = Package(
    name: "bandje-core",
    platforms: [.macOS(.v15), .iOS("26.0")],
    products: [
        .library(name: "BandjeKit", targets: ["BandjeKit"]),
    ],
    targets: [
        .target(name: "BandjeKit", path: "Sources/BandjeKit"),
        .testTarget(name: "BandjeKitTests", dependencies: ["BandjeKit"], path: "Tests/BandjeKitTests"),
    ]
)
