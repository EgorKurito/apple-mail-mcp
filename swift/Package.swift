// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mail-bridge",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "mail-bridge",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MailBridge",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
