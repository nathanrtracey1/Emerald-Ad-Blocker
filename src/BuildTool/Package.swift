// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmeraldBuildTool",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/AdguardTeam/SafariConverterLib.git", from: "4.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "EmeraldBuildTool",
            dependencies: [
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib"),
            ],
            path: "Sources"
        )
    ]
)
