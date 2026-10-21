# WendySwift

The Wendy SDK for Swift, built on [Wendy Core](https://github.com/wendylabsinc/wendy-core).

```swift
import WendySwift

let value = Wendy.helloWorld() // 42, computed by Wendy Core
```

WendySwift is the Swift API for Wendy's apps (starting with Companion) and for third-party apps. It depends on Wendy Core's thin `WendyCore` Swift product, which links the shared Go engine statically. Shared behavior belongs in Wendy Core, so a fix there reaches every client and language; this SDK adds Swift conveniences on top, not separate product behavior.

This is a scaffold: `helloWorld()` is a temporary operation that proves the SDK reaches the shared engine. Real APIs move in step by step.

Platforms: macOS 15+, iOS 18+ (device and Simulator), Linux x64 (glibc 2.35+) and arm64 (glibc 2.39+). Requires Swift 6.2+. Each process should link at most one Go-based library.

## Wendy Core dependency

`Package.swift` depends on `https://github.com/wendylabsinc/wendy-core.git` from `0.0.1`. That release carries Wendy Core's prebuilt static libraries, so `swift test` needs no Go compiler; CI tests against it.

To change Wendy Core and WendySwift together, build against a local checkout instead:

```sh
git clone https://github.com/wendylabsinc/wendy-core.git ../wendy-core
python3 ../wendy-core/scripts/build.py swift   # static Go libraries for this host; needs Go
WENDY_CORE_PATH="$PWD/../wendy-core" swift test
```

The checkout directory must be named `wendy-core`, the package identity used in `Package.swift`.

## License

Apache License 2.0; see [LICENSE](LICENSE).
