// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ZooTV", platforms: [.macOS(.v14), .tvOS(.v17)], products: [
    .library(name: "ZooTVCore", targets: ["ZooTVCore"]),
    .executable(name: "zootv-check", targets: ["ZooTVCheck"])
], targets: [
    .target(name: "ZooTVCore", path: "Core"),
    .executableTarget(name: "ZooTVCheck", dependencies: ["ZooTVCore"], path: "Tools"),
    .testTarget(name: "ZooTVCoreTests", dependencies: ["ZooTVCore"], path: "Tests/CoreTests")
])
