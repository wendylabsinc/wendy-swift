#if WENDY_BRIDGE_TESTS
import BridgeSupport
import Foundation
import Synchronization
import Testing
@testable import WendySwift

private struct BridgeResult: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        var Name: String
        var Value: [UInt8]?
    }
    var Message: [UInt8]?
    var Certificates: [[UInt8]]?
    var Messages: [[UInt8]?]?
    var Initial: [Metadata]?
    var Trailing: [Metadata]?
    var Code: UInt32
    var Error: String
    var StatusMessage: String
    var Cancelled: Bool
}

private func invoke(_ handle: UInt64, operation: UInt32, timeout: Int64 = 5_000) async throws -> BridgeResult {
    // A synchronous Go caller must use a dedicated OS thread. Task.detached
    // still uses Swift's cooperative pool and would starve host callback tasks
    // when many C callers are waiting concurrently.
    let data: Data = await withCheckedContinuation { continuation in
        Thread.detachNewThread {
            let pointer = WendySwiftTestInvoke(handle, operation, timeout)!
            defer { free(pointer) }
            continuation.resume(returning: Data(String(cString: pointer).utf8))
        }
    }
    // Go encodes []byte as base64, unlike ordinary JSON arrays.
    let decoder = JSONDecoder()
    return try decoder.decode(BridgeResult.self, from: normalizeBytes(data))
}

private func normalizeBytes(_ data: Data) throws -> Data {
    func normalize(_ value: Any, key: String = "") -> Any {
        if let string = value as? String, ["Message", "Value"].contains(key) {
            return Data(base64Encoded: string).map { Array($0) } ?? []
        }
        if let list = value as? [Any] {
            return list.map { item -> Any in
                if ["Messages", "Certificates"].contains(key), let string = item as? String {
                    return Array(Data(base64Encoded: string)!)
                }
                return normalize(item, key: key)
            }
        }
        if let object = value as? [String: Any] {
            return object.mapValues { $0 }.reduce(into: [String: Any]()) { output, item in
                output[item.key] = normalize(item.value, key: item.key)
            }
        }
        return value
    }
    return try JSONSerialization.data(withJSONObject: normalize(JSONSerialization.jsonObject(with: data)))
}

private struct FakeSigner: Signer {
    var algorithm = "ML-DSA-65"
    var signBody: @Sendable ([UInt8]) async throws -> [UInt8] = { $0.reversed() }
    func sign(_ message: [UInt8]) async throws -> [UInt8] { try await signBody(message) }
    func certificateChain() async throws -> [[UInt8]] { [[1, 0, 255], [2]] }
    func publicKey() async throws -> [UInt8] { [3, 0, 255] }
}

private let headers = [RPCMetadataEntry(name: "header-bin", value: [0, 255])]
private let trailers = [RPCMetadataEntry(name: "trailer", value: Array("done".utf8))]

private struct FakeTransport: Transport {
    var unaryBody: @Sendable (RPCRequest) async throws -> RPCResponse = { request in
        #expect(request.method == "/test.Service/Call")
        #expect(request.message == [0, 255, 42])
        #expect(request.metadata == [
            RPCMetadataEntry(name: "value", value: Array("one".utf8)),
            RPCMetadataEntry(name: "value", value: Array("two".utf8)),
            RPCMetadataEntry(name: "raw-bin", value: [0, 255]),
        ])
        #expect(request.deadlineUnixMilliseconds != nil)
        return RPCResponse(message: request.message, initialMetadata: headers, trailingMetadata: trailers)
    }
    var stream: any ServerStream = FakeStream()
    var openingError: RPCStatusError? = nil
    func unary(_ request: RPCRequest) async throws -> RPCResponse { try await unaryBody(request) }
    func serverStream(_ request: RPCRequest) async throws -> any ServerStream {
        if let openingError { throw openingError }
        return stream
    }
}

private actor FakeStream: ServerStream {
    var index = 0
    let terminal: RPCStatusError?
    let closed = Mutex(false)
    func wasClosed() -> Bool { closed.withLock { $0 } }
    init(terminal: RPCStatusError? = nil) { self.terminal = terminal }
    nonisolated func close() { closed.withLock { $0 = true } }
    func initialMetadata() -> [RPCMetadataEntry] { headers }
    func next() throws -> [UInt8]? {
        defer { index += 1 }
        switch index {
        case 0: return [0, 255]
        case 1: return []
        case 2: return [42]
        default:
            if let terminal { throw terminal }
            return nil
        }
    }
    func trailingMetadata() -> [RPCMetadataEntry] { trailers }
}

@Test func `registers and completes signing with copied binary bytes`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport())
    defer { host.close() }
    #expect(host.handle != 0)
    let signed = try await invoke(host.handle, operation: 1)
    #expect(signed.Message == [42, 255, 0])
    #expect(signed.Error.isEmpty)
    let certificates = try await invoke(host.handle, operation: 2)
    #expect(certificates.Certificates == [[1, 0, 255], [2]])
    let key = try await invoke(host.handle, operation: 3)
    #expect(key.Message == [3, 0, 255])
}

@Test func `rejects an empty algorithm without transferring ownership`() throws {
    #expect(throws: HostRegistrationError.self) {
        try HostRegistration(signer: FakeSigner(algorithm: ""), transport: FakeTransport())
    }
}

@Test func `preserves unary messages metadata and deadlines`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport())
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 4)
    #expect(result.Message == [0, 255, 42])
    #expect(result.Initial?.first?.Value == [0, 255])
    #expect(result.Trailing?.first?.Name == "trailer")
    #expect(result.Error.isEmpty)
}

@Test func `preserves unknown status codes diagnostics and trailers`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport(unaryBody: { _ in
        throw RPCStatusError(code: 99, message: "original diagnostic", initialMetadata: headers, trailingMetadata: trailers)
    }))
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 4)
    #expect(result.Code == 99)
    #expect(result.StatusMessage == "original diagnostic")
    #expect(result.Initial?.first?.Value == [0, 255])
    #expect(result.Trailing?.first?.Name == "trailer")
}

@Test func `does not leak arbitrary host error descriptions`() async throws {
    struct SecretError: Error { let credential = "do-not-expose" }
    let host = try HostRegistration(signer: FakeSigner(signBody: { _ in throw SecretError() }), transport: FakeTransport())
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 1)
    #expect(result.Code == 13)
    #expect(result.StatusMessage == "Host capability failed")
    #expect(!result.Error.contains("do-not-expose"))
}

@Test func `streams ordered binary and empty messages with headers and trailers`() async throws {
    let stream = FakeStream()
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport(stream: stream))
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 5)
    #expect(result.Messages == [[0, 255], [], [42]])
    #expect(result.Initial?.first?.Value == [0, 255])
    #expect(result.Trailing?.first?.Name == "trailer")
    #expect(result.Error.isEmpty)
    try await waitUntil { await stream.wasClosed() }
}

@Test func `delivers accepted stream items before terminal status`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport(stream: FakeStream(
        terminal: RPCStatusError(code: 7, message: "stream denied", trailingMetadata: trailers))))
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 5)
    #expect(result.Messages == [[0, 255], [], [42]])
    #expect(result.Code == 7)
    #expect(result.Trailing?.first?.Name == "trailer")
}

private actor CancellationProbe {
    var started = false
    var cancelled = false
    func run() async throws -> [UInt8] {
        started = true
        do { try await Task.sleep(for: .seconds(60)) } catch { cancelled = true; throw error }
        return []
    }
}

private func waitUntil(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw RPCStatusError(code: 4, message: "Test wait timed out") }
        try await Task.sleep(for: .milliseconds(1))
    }
}

@Test func `deadline cancellation cancels the Swift task`() async throws {
    let probe = CancellationProbe()
    let host = try HostRegistration(signer: FakeSigner(signBody: { _ in try await probe.run() }), transport: FakeTransport())
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 1, timeout: 100)
    #expect(result.Cancelled)
    try await waitUntil { await probe.cancelled }
}

@Test func `release cancels active work and rejects subsequent calls`() async throws {
    let probe = CancellationProbe()
    let host = try HostRegistration(signer: FakeSigner(signBody: { _ in try await probe.run() }), transport: FakeTransport())
    async let pending = invoke(host.handle, operation: 1)
    try await waitUntil { await probe.started }
    host.close()
    host.close()
    #expect(try await pending.Cancelled)
    try await waitUntil { await probe.cancelled }
    #expect(try await invoke(host.handle, operation: 1).Cancelled)
}

@Test func `late completion after cancellation is harmless`() async throws {
    let completed = Mutex(false)
    let host = try HostRegistration(signer: FakeSigner(signBody: { _ in
        // Deliberately ignore cancellation to exercise Core's late-completion rule.
        await Task.detached { try? await Task.sleep(for: .milliseconds(150)) }.value
        completed.withLock { $0 = true }
        return [42]
    }), transport: FakeTransport())
    let result = try await invoke(host.handle, operation: 1, timeout: 20)
    host.close()
    #expect(result.Cancelled)
    try await waitUntil { completed.withLock { $0 } }
}

@Test func `deinitialization releases the Core registration`() async throws {
    var host: HostRegistration? = try HostRegistration(signer: FakeSigner(), transport: FakeTransport())
    let handle = host!.handle
    host = nil
    #expect(try await invoke(handle, operation: 1).Cancelled)
}
@Test func `concurrent host calls keep their completions isolated`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport())
    defer { host.close() }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<32 {
            group.addTask {
                let result = try await invoke(host.handle, operation: 1)
                #expect(result.Message == [42, 255, 0])
                #expect(result.Error.isEmpty)
            }
        }
        try await group.waitForAll()
    }
}

@Test func `opening a stream preserves status and metadata`() async throws {
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport(
        openingError: RPCStatusError(code: 16, message: "stream rejected", initialMetadata: headers, trailingMetadata: trailers)))
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 5)
    #expect(result.Code == 16)
    #expect(result.StatusMessage == "stream rejected")
    #expect(result.Initial?.first?.Value == [0, 255])
    #expect(result.Trailing?.first?.Name == "trailer")
}

private actor BlockingStream: ServerStream {
    let probe = CancellationProbe()
    let closed = Mutex(false)
    func initialMetadata() -> [RPCMetadataEntry] { headers }
    func next() async throws -> [UInt8]? { try await probe.run() }
    func trailingMetadata() -> [RPCMetadataEntry] { [] }
    nonisolated func close() { closed.withLock { $0 = true } }
    func wasClosed() -> Bool { closed.withLock { $0 } }
}

@Test func `stream deadline cancels blocked reads and closes host resources`() async throws {
    let stream = BlockingStream()
    let host = try HostRegistration(signer: FakeSigner(), transport: FakeTransport(stream: stream))
    defer { host.close() }
    let result = try await invoke(host.handle, operation: 5, timeout: 100)
    #expect(result.Cancelled)
    try await waitUntil { await stream.wasClosed() }
    #expect(await stream.probe.cancelled)
}
#endif
