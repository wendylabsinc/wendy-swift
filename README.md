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
`0.1.0`, which is unreleased. `Wendy.coreVersion` requires the version API in that
release. Once released, Core will carry prebuilt static libraries, so consumers
will not need a Go compiler.

Until then, build against a local checkout of Core's version-API branch. The same
approach lets you change Wendy Core and WendySwift together:

```sh
git clone https://github.com/wendylabsinc/wendy-core.git ../wendy-core
git -C ../wendy-core checkout kb.sdk.2 # Version API, until Core 0.1.0 ships
python3 ../wendy-core/scripts/build.py swift   # static Go libraries for this host; needs Go
WENDY_CORE_PATH="$PWD/../wendy-core" swift test
```

The checkout directory must be named `wendy-core`, the package identity used in `Package.swift`.

Core's branches, including `main`, need locally built binaries and cannot be
consumed directly as remote SwiftPM dependencies. The build requires Go (see
Core's `.go-version`) and, on macOS, Xcode. On macOS it builds the macOS, iOS and
iOS Simulator libraries; on Linux it builds for the host architecture. CI uses a
pinned Core source commit until the released dependency is available.

## License

Apache License 2.0; see [LICENSE](LICENSE).
