// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bandje",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", exact: "4.2.3"),
    ],
    targets: [
        .executableTarget(
            name: "Bandje",
            dependencies: [
                .product(name: "Voz", package: "desert-ant-core"),
                .product(name: "Who", package: "desert-ant-core"),
            ],
            path: "Sources/Bandje",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BandjeTests",
            dependencies: ["Bandje"],
            path: "Tests/BandjeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
