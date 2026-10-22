# WendySwift

The Wendy SDK for Swift, built on [Wendy Core](https://github.com/wendylabsinc/wendy-core).

```swift
import WendySwift

let value = Wendy.helloWorld() // 42, computed by Wendy Core
let coreVersion = Wendy.coreVersion // Version reported by the linked Core engine
```

WendySwift is the Swift API for Wendy's apps (starting with Companion) and for third-party apps. It depends on Wendy Core's thin `WendyCore` Swift product, which links the shared Go engine statically. Shared behavior belongs in Wendy Core, so a fix there reaches every client and language; this SDK adds Swift conveniences on top, not separate product behavior.

This is a scaffold: `helloWorld()` is a temporary operation that proves the SDK reaches the shared engine. Real APIs move in step by step.

Platforms: macOS 15+, iOS 18+ (device and Simulator), Linux x64 (glibc 2.35+) and arm64 (glibc 2.39+). Requires Swift 6.2+. Each process should link at most one Go-based library.

## Wendy Core dependency

`Package.swift` depends on `https://github.com/wendylabsinc/wendy-core.git` from
`0.1.0-seed.1`. [Wendy Core 0.1.0-seed.1](https://github.com/wendylabsinc/wendy-core/releases/tag/v0.1.0-seed.1)
provides the version API and prebuilt static libraries, so `swift test` and CI
resolve the released binaries without a Go compiler.

Consumers of WendySwift's first seed must explicitly allow pre-releases:

```swift
.package(url: "https://github.com/wendylabsinc/wendy-swift.git", from: "0.1.0-seed.1")
```

Use `from: "0.1.0-seed.1"` or a later seed as the lower bound. SwiftPM excludes
pre-releases unless the requirement names one. This range also accepts later
seeds and the stable `0.1.0` release. WendySwift's planned `v0.1.0-seed.1` tag
resolves as version `0.1.0-seed.1` in SwiftPM.

`Wendy.coreVersion` returns the linked Core binary's stamped build identity
unchanged: `0.1.0-seed.1` with that release. Local Core builds report
`<VERSION>-dev+<7-character commit>`, using the Core checkout's commit.
WendySwift does not derive its own version string.

To develop Wendy Core and WendySwift together, optionally build against a local
Core checkout instead:

```sh
git clone https://github.com/wendylabsinc/wendy-core.git ../wendy-core
python3 ../wendy-core/scripts/build.py swift   # static Go libraries for this host; needs Go
WENDY_CORE_PATH="$PWD/../wendy-core" swift test
```

The checkout directory must be named `wendy-core`, the package identity used in `Package.swift`.

This optional local build requires Go (see Core's `.go-version`) and, on macOS,
Xcode. On macOS it builds the macOS, iOS and iOS Simulator libraries; on Linux it
builds for the host architecture.

## License

Apache License 2.0; see [LICENSE](LICENSE).
