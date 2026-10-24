// swift-tools-version: 6.2
import Foundation
import PackageDescription

// WENDY_CORE_PATH names WendyOS/go/wendy-core after scripts/build.py swift.
// Release tags replace only this block with checksummed binary URLs.
// BEGIN BINARY TARGETS
let binaryTargets: [Target] = [
    .binaryTarget(name: "CWendyCoreApple", url: "https://github.com/wendylabsinc/wendy-swift/releases/download/0.1.0-seed.2/CWendyCore.xcframework.zip", checksum: "23b329c6fb3d181203e69e8a37b4a54467b1b25b88d42f6e48f6a34a3740d87e"),
    .binaryTarget(name: "CWendyCoreLinux", url: "https://github.com/wendylabsinc/wendy-swift/releases/download/0.1.0-seed.2/CWendyCore.artifactbundle.zip", checksum: "78bac5532cb617e3061cfbb338f1a541dd2852b90a1940590d3e1f6f5a57e649"),
]
// END BINARY TARGETS

let binaryPlatforms: [String: [Platform]] = [
    "CWendyCoreApple": [.macOS, .iOS], "CWendyCoreLinux": [.linux],
]
let coreDependencies: [Target.Dependency] = binaryTargets.map {
    .target(name: $0.name, condition: .when(platforms: binaryPlatforms[$0.name, default: []]))
}
let bridgeTests = Context.environment["WENDY_BRIDGE_TESTS"] == "1"
let package = Package(
    name: "wendy-swift",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "WendySwift", targets: ["WendySwift"]),
        .library(name: "WendyCore", targets: ["WendyCore"]),
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0")],
    targets: binaryTargets + [
        .target(name: "WendyCore", dependencies: coreDependencies,
                swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")],
                linkerSettings: [.linkedFramework("CoreFoundation", .when(platforms: [.iOS]))]),
        .target(name: "WendySwift", dependencies: ["WendyCore", .product(name: "SwiftProtobuf", package: "swift-protobuf")] + coreDependencies,
                swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")]),
        .target(name: "BridgeSupport", path: "Tests/BridgeSupport", exclude: ["driver.go.txt"]),
        .testTarget(name: "WendySwiftTests", dependencies: ["WendySwift", "WendyCore", "BridgeSupport", .product(name: "SwiftProtobuf", package: "swift-protobuf")],
                    swiftSettings: bridgeTests ? [.define("WENDY_BRIDGE_TESTS")] : []),
    ]
)
