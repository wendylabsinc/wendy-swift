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
    let path = corePath + "/distributions/swift/artifacts/" + file
    return FileManager.default.fileExists(atPath: Context.packageDirectory + "/" + path)
        || FileManager.default.fileExists(atPath: path)
        ? .binaryTarget(name: name, path: path) : nil
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
    targets: binaryTargets + [
        .target(name: "WendyCore", dependencies: coreDependencies,
                swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")],
                linkerSettings: [.linkedFramework("CoreFoundation", .when(platforms: [.iOS]))]),
        .target(name: "WendySwift", dependencies: ["WendyCore"] + coreDependencies,
                swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")]),
        .target(name: "BridgeSupport", path: "Tests/BridgeSupport", exclude: ["driver.go.txt"]),
        .testTarget(name: "WendySwiftTests", dependencies: ["WendySwift", "WendyCore", "BridgeSupport"],
                    swiftSettings: bridgeTests ? [.define("WENDY_BRIDGE_TESTS")] : []),
    ]
)
