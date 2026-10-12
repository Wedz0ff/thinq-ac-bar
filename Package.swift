// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ACBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ACBar", path: "Sources/ACBar"),
        .testTarget(name: "ACBarTests", dependencies: ["ACBar"], path: "Tests/ACBarTests"),
    ]
)
