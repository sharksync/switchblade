// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Switchblade",
    platforms: [
            .macOS(.v10_14)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Switchblade",
            targets: ["Switchblade"]),
    ],
    dependencies: [
        .package(url: "https://github.com/VeldsparCrypto/CSQlite.git",      .exact("1.0.9")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git",   .upToNextMinor(from: "1.3.8")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Switchblade",
            dependencies: ["CryptoSwift"],
            path: "./Sources/switchblade"),
        .testTarget(
            name: "SwitchbladeTests",
            dependencies: ["Switchblade"],
            path: "./Tests/switchbladeTests"),
    ]
)
