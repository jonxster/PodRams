// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PodRams",
    platforms: [.macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PodRams",
            targets: ["PodRams"]),
    ],
    dependencies: [
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PodRams",
            dependencies: ["FeedKit"],
            path: ".",
            exclude: ["PodRamsTests", "PodRamsUITests", "Package.swift"],
            sources: ["."],
            resources: [.copy("Resources")]),
        .testTarget(
            name: "PodRamsTests",
            dependencies: ["PodRams"],
            path: "PodRamsTests"),
    ]
)
