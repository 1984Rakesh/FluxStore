// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FluxStore",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "FluxStore", targets: ["FluxStore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "FluxStore", dependencies: [])
    ],
    swiftLanguageVersions: [
        .version("5.2")
    ]
)
