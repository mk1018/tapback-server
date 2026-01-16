// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TapbackApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "TapbackApp", targets: ["TapbackApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "TapbackApp",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
    ]
)
