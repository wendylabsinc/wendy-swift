// swift-tools-version: 6.2
import Foundation
import PackageDescription

// WENDY_CORE_PATH names WendyOS/go/wendy-core after scripts/build.py swift.
// Release tags replace only this block with checksummed binary URLs.
// BEGIN BINARY TARGETS
let corePath = Context.environment["WENDY_CORE_PATH"] ?? ".build/WendyOS/go/wendy-core"
let binaryTargets: [Target] = [
    ("CWendyCoreApple", "CWendyCore.xcframework"),
    ("CWendyCoreLinux", "CWendyCore.artifactbundle"),
].compactMap { name, file in
    let root = URL(fileURLWithPath: Context.packageDirectory, isDirectory: true)
    let artifact = URL(fileURLWithPath: corePath, relativeTo: root)
        .appendingPathComponent("distributions/swift/artifacts/" + file).standardizedFileURL
    guard FileManager.default.fileExists(atPath: artifact.path) else { return nil }
    // SwiftPM requires relative binary paths, including for absolute overrides.
    let base = root.standardizedFileURL.pathComponents
    let parts = artifact.pathComponents
    let common = zip(base, parts).prefix { $0 == $1 }.count
    let path = (Array(repeating: "..", count: base.count - common) + parts.dropFirst(common)).joined(separator: "/")
    return .binaryTarget(name: name, path: path)
}
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
