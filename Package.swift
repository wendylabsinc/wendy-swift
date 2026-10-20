// swift-tools-version: 6.2
import PackageDescription

// WENDY_CORE_PATH selects a local wendy-core checkout whose Swift binaries were
// built with `make swift` there. CI uses it, as does development until Wendy
// Core publishes its first Swift release.
let core: Package.Dependency = if let path = Context.environment["WENDY_CORE_PATH"] {
    .package(path: path)
} else {
    .package(url: "https://github.com/wendylabsinc/wendy-core.git", from: "0.1.0")
}

let package = Package(
    name: "wendy-swift",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "WendySwift", targets: ["WendySwift"])],
    dependencies: [core],
    targets: [
        .target(
            name: "WendySwift",
            dependencies: [.product(name: "WendyCore", package: "wendy-core")],
            swiftSettings: [.enableUpcomingFeature("InternalImportsByDefault")]
        ),
        .testTarget(name: "WendySwiftTests", dependencies: ["WendySwift"]),
    ]
)
