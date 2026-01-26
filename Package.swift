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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "e81c583ba0d9e5aaa9081003bd8605e95d7fe2bc"),
    ],
    targets: [
        .executableTarget(
            name: "TapbackApp",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
            ]
        ),
    ]
)
