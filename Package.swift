// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCAccountManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CCAccountManager", targets: ["CCAccountManager"])
    ],
    targets: [
        .executableTarget(
            name: "CCAccountManager",
            path: "Sources/CCAccountManager"
        )
    ]
)
