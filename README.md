# WendySwift

The Swift SDK over the shared [Wendy Core engine in WendyOS](https://github.com/wendylabsinc/WendyOS/tree/main/go/wendy-core).

```swift
import WendySwift

let value = Wendy.helloWorld() // 42, computed by Core
let version = Wendy.coreVersion
```

Shared product behavior lives in Core. Swift supplies host capabilities through
`Signer`, `Transport` and `Entropy`: private keys, signing, TLS, networking and
secure random bytes stay with the host. `SystemEntropy` is the default entropy source. `HostRegistration` connects these async, Sendable capabilities to Core's
C interface. Keep the registration alive for operations using its handle; call
`close()` to cancel outstanding work (deinitialization also closes it).
`ServerStream.next()` receives one message per Core request, without a binding
prefetch queue. Hosts honor task cancellation and RPC deadlines, validate
metadata, and retain remote status codes and trailers in `RPCStatusError`.

`CloudClient(host:authority:)` lists Cloud devices through Core:

```swift
let client = CloudClient(host: host, authority: "cloud.example:443")
let devices = try await client.cloudDevices(
    organizationID: tenantUUID, accessToken: boundAccessToken)
```

The host must validate its ML-DSA-65 key and token/tenant binding and bind its TLS
transport to the authority before calling. `organizationID` is the immutable
tenant UUID. Token refresh and connections remain host responsibilities.
`CloudDevice` aliases the published Cloud v2 `Asset` protobuf, preserving optional
and unknown fields. SwiftProtobuf supplies serialization. Core returns a complete
bounded list or an error, with no public offset API or snapshot guarantee. Task
cancellation cancels Core and throws `CancellationError`; other errors retain
numeric gRPC status (including deadline code 4) and ordered binary metadata in
`RPCStatusError`. Keep remote diagnostics and metadata out of logs.

Cloud tests exercise the production C operation with fake capabilities. The
other host bridge tests use a test-only Go caller. The binding adds no product
logic or encryption.

Platforms: macOS 15+, iOS 18+ (device and Simulator), Linux x64 (glibc 2.35+)
and arm64 (glibc 2.39+). Requires Swift 6.2+. Each process must link at most one
Go-based library. Link WendySwift/WendyCore into the app only, never its network
extension. Companion's `CheckCoreLinkage.py` guards that boundary.

## Local development

Main uses local binaries; it has no SwiftPM URL dependency on the old Core repo.
The exact WendyOS source is pinned in `scripts/core-revision`. Core's own build
script creates the XCFramework on macOS and the host Linux artifact bundle on
Linux. Install Go (Core's `.go-version`), Python 3 and a C compiler; Apple builds
also need Xcode and XcodeBuildMCP.

```sh
git clone https://github.com/wendylabsinc/WendyOS.git .build/WendyOS
git -C .build/WendyOS checkout --detach "$(cat scripts/core-revision)"
python3 scripts/build-core.py
# macOS (the repo's XcodeBuildMCP path)
xcodebuildmcp swift-package test --package-path "$PWD"
# Linux
swift test
```

`WENDY_CORE_PATH` can instead name another checkout's `go/wendy-core` directory
with prebuilt `distributions/swift/artifacts/` binaries. It is no longer a
SwiftPM package dependency. `build-core.py` checks that checkout against the pin
and must run only in your own checkout, since it writes build artifacts.

For the full host bridge tests, rebuild with the test-only Go caller:

```sh
python3 scripts/build-core.py --test-host
WENDY_BRIDGE_TESTS=1 xcodebuildmcp swift-package test --package-path "$PWD" # macOS
WENDY_BRIDGE_TESTS=1 swift test # Linux
```

The test caller is compiled into the same Go archive, so it adds no second Go
runtime. Rebuild without `--test-host` for production. CI runs these tests on
both Linux architectures and macOS, and compiles/links them for iOS device and
Simulator without booting a simulator. iOS tests are not executed.

To regenerate the checked-in Swift messages, build `protoc-gen-swift` from
SwiftProtobuf 1.39.0, then run `python3 scripts/generate-protobuf.py --plugin
/path/to/protoc-gen-swift`. It reads the pinned checkout's Core envelope and
projects the unchanged Cloud `Asset`/`AssetKind` declarations, omitting unrelated
service operations.

## Pre-release packaging

An authorized release owner pushes `swift-preview/<0.1.x-prerelease>` at the
source commit. The release workflow builds production Core binaries from the
pin, tests them, assembles both Linux variants and the Apple XCFramework, then
creates a release-only commit rewriting the binary target URLs and SHA-256
checksums. The bare `<0.1.x-prerelease>` SwiftPM tag points at that commit; the
matching GitHub pre-release owns the assets. Main retains local-build mode.
Stable releases are deliberately unsupported by this workflow.

Consumers use the bare pre-release version explicitly, for example:

```swift
.package(url: "https://github.com/wendylabsinc/wendy-swift.git", exact: "0.1.0-seed.2")
```

That version is illustrative; this change creates no release. Pre-release
requirements must name a pre-release. The linked engine reports its own stamped
Core build identity independently of the SDK version. Release retries reuse
existing tags and assets; an existing version cannot be replaced.

## License

Apache License 2.0; see [LICENSE](LICENSE). Core archives retain Core's Apache
notice and the Go runtime's BSD license.
