// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RedlineMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Redline", targets: ["Redline"])
    ],
    targets: [
        .executableTarget(
            name: "Redline",
            path: "Sources/Redline"
        ),
        .testTarget(
            name: "RedlineTests",
            dependencies: ["Redline"],
            path: "Tests/RedlineTests"
        )
    ]
)

