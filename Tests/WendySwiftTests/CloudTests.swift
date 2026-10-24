import Foundation
import SwiftProtobuf
import Synchronization
import Testing
@testable import WendySwift

private let tenant = "12345678-1234-1234-1234-123456789abc"
private let authority = "cloud.example:443"
private let method = "/wendycloud.v2.AssetService/ListAssets"

private struct CloudSigner: Signer {
    let algorithm = "ML-DSA-65"
    var signing: @Sendable ([UInt8]) async throws -> [UInt8] = { _ in [0, 255, 42] }
    func certificateChain() async throws -> [[UInt8]] { [] }
    func publicKey() async throws -> [UInt8] {
        // Structurally valid ML-DSA-65 SPKI. Only this fake skips key verification.
        [0x30, 0x82, 0x07, 0xb2, 0x30, 0x0b, 0x06, 0x09, 0x60, 0x86, 0x48,
         0x01, 0x65, 0x03, 0x04, 0x03, 0x12, 0x03, 0x82, 0x07, 0xa1, 0] + Array(repeating: 0, count: 1952)
    }
    func sign(_ message: [UInt8]) async throws -> [UInt8] { try await signing(message) }
}

private final class CloudEntropy: Entropy {
    let counts = Mutex<[Int]>([])
    var requestedCounts: [Int] { counts.withLock { $0 } }
    func randomBytes(count: Int) async throws -> [UInt8] {
        counts.withLock { $0.append(count) }
        return Array(repeating: 42, count: count)
    }
}

private struct CloudTransport: Transport {
    var open: @Sendable (RPCRequest) async throws -> any ServerStream
    func unary(_ request: RPCRequest) async throws -> RPCResponse {
        Issue.record("Device listing must use the streaming Cloud RPC")
        throw RPCStatusError(code: 12, message: "Unexpected unary call")
    }
    func serverStream(_ request: RPCRequest) async throws -> any ServerStream { try await open(request) }
}

private actor CloudStream: ServerStream {
    let items: [[UInt8]]
    let terminal: RPCStatusError?
    let closed = Mutex(false)
    var index = 0
    init(items: [[UInt8]], terminal: RPCStatusError? = nil) { self.items = items; self.terminal = terminal }
    func initialMetadata() -> [RPCMetadataEntry] { terminal?.initialMetadata ?? [] }
    func trailingMetadata() -> [RPCMetadataEntry] { [] }
    func next() throws -> [UInt8]? {
        guard index < items.count else {
            if let terminal { throw terminal }
            return nil
        }
        defer { index += 1 }
        return items[index]
    }
    nonisolated func close() { closed.withLock { $0 = true } }
}

private func varint(_ value: Int) -> [UInt8] {
    var value = value
    var result: [UInt8] = []
    while value >= 128 { result.append(UInt8(value & 127) | 128); value >>= 7 }
    return result + [UInt8(value)]
}

private func page(_ asset: CloudDevice, total: Int) throws -> [UInt8] {
    // The existing Cloud ListAssetsResponse: asset (field 1), total (field 2).
    let wire: [UInt8] = try asset.serializedBytes()
    return [0x0a] + varint(wire.count) + wire + [0x10] + varint(total)
}

private func device(_ id: String) throws -> CloudDevice {
    var asset = CloudDevice()
    asset.id = id; asset.organizationID = tenant; asset.name = "robot"
    asset.isComputeDevice = true; asset.displayName = "Robot 🐕"
    asset.tags = ["test", "lab"]; asset.site = ""; asset.cpuCores = 0
    // Include an unknown field to verify the published schema survives Core/Swift.
    let bytes: [UInt8] = try asset.serializedBytes()
    return try CloudDevice(serializedBytes: bytes + [0xa0, 0x1f, 42]) // field 500
}

private actor Inventory {
    let assets: [CloudDevice]
    var requests: [RPCRequest] = []
    init(assets: [CloudDevice]) { self.assets = assets }
    func open(_ request: RPCRequest) throws -> any ServerStream {
        let index = requests.count
        requests.append(request)
        guard index < assets.count else { throw RPCStatusError(code: 13, message: "Unexpected extra page") }
        return CloudStream(items: [try page(assets[index], total: assets.count)])
    }
}

@Test func `lists complete Cloud inventory through real Core with host proofs`() async throws {
    let assets = try [device("first"), device("second")]
    let inventory = Inventory(assets: assets)
    let entropy = CloudEntropy()
    let signed = Mutex<[[UInt8]]>([])
    let host = try HostRegistration(signer: CloudSigner(signing: { bytes in
        signed.withLock { $0.append(bytes) }; return [0, 255, 42]
    }), transport: CloudTransport(open: { try await inventory.open($0) }), entropy: entropy)
    defer { host.close() }
    let deadline = Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1000)
    let result = try await CloudClient(host: host, authority: authority).cloudDevices(
        organizationID: tenant, accessToken: "test-token", filter: "robot", onlineOnly: true,
        deadlineUnixMilliseconds: deadline)
    #expect(result == assets)
    #expect(result[0].displayName == "Robot 🐕")
    #expect(result[0].hasSite && result[0].site.isEmpty)
    #expect(result[0].hasCpuCores && result[0].cpuCores == 0)
    #expect(!result[0].hasArchitecture)
    #expect(!result[0].unknownFields.data.isEmpty)
    let requests = await inventory.requests
    #expect(requests.count == 2)
    for (offset, request) in requests.enumerated() {
        #expect(request.method == method)
        #expect(request.deadlineUnixMilliseconds == deadline)
        // Canonical Cloud ListAssetsRequest; Core alone supplies paging selectors.
        var expectedRequest: [UInt8] = [0x0a, 36]
        expectedRequest += tenant.utf8
        expectedRequest += [0x10, 1, 0x18, UInt8(offset), 0x20, 0xc8, 1, 0x2a, 5]
        expectedRequest += "robot".utf8
        expectedRequest += [0x30, 1]
        #expect(request.message == expectedRequest)
        #expect(request.metadata.first { $0.name == "authorization" }?.value == Array("DPoP test-token".utf8))
        #expect(request.metadata.contains { $0.name == "x-correlation-id" && !$0.value.isEmpty })
        let proof = try #require(request.metadata.first { $0.name == "dpop" })
        #expect(String(decoding: proof.value, as: UTF8.self).split(separator: ".").count == 3)
    }
    #expect(entropy.requestedCounts.count == 3) // correlation ID and one DPoP nonce per page
    let signatures = signed.withLock { $0 }
    #expect(signatures.count == 2)
    for signature in signatures {
        let payload = String(decoding: signature, as: UTF8.self).split(separator: ".")[1]
        let base64 = String(payload).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let data = try #require(Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)))
        let claims = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(claims["htm"] as? String == "POST")
        #expect(claims["htu"] as? String == "https://" + authority + method)
        #expect(claims["ath"] != nil && claims["jti"] != nil)
    }
}

@Test func `returns an empty inventory from Core`() async throws {
    let host = try HostRegistration(signer: CloudSigner(), transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    defer { host.close() }
    #expect(try await CloudClient(host: host, authority: authority).cloudDevices(organizationID: tenant, accessToken: "test-token").isEmpty)
}

@Test(arguments: [UInt32(7), 123])
func `preserves Cloud status and repeated binary metadata without partial results`(code: UInt32) async throws {
    let initial = [RPCMetadataEntry(name: "trace-bin", value: [0, 255]), RPCMetadataEntry(name: "trace-bin", value: [])]
    let trailing = [RPCMetadataEntry(name: "details-bin", value: [255, 0]), RPCMetadataEntry(name: "details-bin", value: [42])]
    let status = RPCStatusError(code: code, message: "remote diagnostic", initialMetadata: initial, trailingMetadata: trailing)
    let item = try page(device("partial"), total: 2)
    let stream = CloudStream(items: [item], terminal: status)
    let host = try HostRegistration(signer: CloudSigner(), transport: CloudTransport(open: { _ in stream }))
    defer { host.close() }
    do {
        _ = try await CloudClient(host: host, authority: authority).cloudDevices(organizationID: tenant, accessToken: "test-token")
        Issue.record("Expected Cloud status")
    } catch let error as RPCStatusError {
        #expect(error == status)
    }
}

private actor CloudBlocker {
    var started = false
    var cancelled = false
    func block() async throws -> [UInt8] {
        started = true
        do { try await Task.sleep(for: .seconds(60)) } catch { cancelled = true; throw error }
        return []
    }
}

private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw RPCStatusError(code: 4, message: "Test wait timed out") }
        try await Task.sleep(for: .milliseconds(1))
    }
}

private actor BlockedCloudStream: ServerStream {
    let blocker: CloudBlocker
    let closed = Mutex(false)
    init(_ blocker: CloudBlocker) { self.blocker = blocker }
    func initialMetadata() -> [RPCMetadataEntry] { [] }
    func next() async throws -> [UInt8]? { try await blocker.block() }
    func trailingMetadata() -> [RPCMetadataEntry] { [] }
    nonisolated func close() { closed.withLock { $0 = true } }
}

@Test(arguments: [true, false])
func `task cancellation reaches host signing and transport reads`(duringSigning: Bool) async throws {
    let blocker = CloudBlocker()
    let stream = BlockedCloudStream(blocker)
    let signer = CloudSigner(signing: { _ in duringSigning ? try await blocker.block() : [42] })
    let host = try HostRegistration(signer: signer, transport: CloudTransport(open: { _ in stream }))
    defer { host.close() }
    let client = CloudClient(host: host, authority: authority)
    let task = Task { try await client.cloudDevices(organizationID: tenant, accessToken: "test-token") }
    try await eventually { await blocker.started }
    task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    try await eventually { await blocker.cancelled }
    if !duringSigning { try await eventually { stream.closed.withLock { $0 } } }
}

@Test func `already cancelled task does not invoke the host`() async throws {
    let calls = Mutex(0)
    let host = try HostRegistration(signer: CloudSigner(signing: { _ in calls.withLock { $0 += 1 }; return [] }),
                                    transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    defer { host.close() }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await CloudClient(host: host, authority: authority).cloudDevices(organizationID: tenant, accessToken: "test-token")
    }
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    #expect(calls.withLock { $0 } == 0)
}

@Test func `Core validates tenant UUID without calling the host`() async throws {
    let calls = Mutex(0)
    let host = try HostRegistration(signer: CloudSigner(signing: { _ in calls.withLock { $0 += 1 }; return [] }),
                                    transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    defer { host.close() }
    do {
        _ = try await CloudClient(host: host, authority: authority).cloudDevices(organizationID: "realm-slug", accessToken: "test-token")
        Issue.record("Expected invalid argument")
    } catch let error as RPCStatusError { #expect(error.code == 3) }
    #expect(calls.withLock { $0 } == 0)
}

@Test func `Cloud deadline cancels blocked host work`() async throws {
    let blocker = CloudBlocker()
    let host = try HostRegistration(signer: CloudSigner(signing: { _ in try await blocker.block() }),
                                    transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    defer { host.close() }
    do {
        _ = try await CloudClient(host: host, authority: authority).cloudDevices(
            organizationID: tenant, accessToken: "test-token",
            deadlineUnixMilliseconds: Int64(Date().addingTimeInterval(0.2).timeIntervalSince1970 * 1000))
        Issue.record("Expected deadline")
    } catch let error as RPCStatusError { #expect(error.code == 4) }
    try await eventually { await blocker.cancelled }
}

@Test func `concurrent Cloud operations keep results isolated`() async throws {
    let item = try page(device("concurrent"), total: 1)
    let host = try HostRegistration(signer: CloudSigner(), transport: CloudTransport(open: { _ in CloudStream(items: [item]) }))
    defer { host.close() }
    let client = CloudClient(host: host, authority: authority)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<32 {
            group.addTask {
                let devices = try await client.cloudDevices(organizationID: tenant, accessToken: "test-token")
                #expect(devices.map(\.id) == ["concurrent"])
            }
        }
        try await group.waitForAll()
    }
}

@Test func `closing the registration cancels an active Cloud operation`() async throws {
    let blocker = CloudBlocker()
    let host = try HostRegistration(signer: CloudSigner(signing: { _ in try await blocker.block() }),
                                    transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    let client = CloudClient(host: host, authority: authority)
    let task = Task { try await client.cloudDevices(organizationID: tenant, accessToken: "test-token") }
    try await eventually { await blocker.started }
    host.close()
    host.close()
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    try await eventually { await blocker.cancelled }
}

@Test func `late host completion after Cloud task cancellation is ignored`() async throws {
    let started = Mutex(false)
    let finished = Mutex(false)
    let signer = CloudSigner(signing: { _ in
        started.withLock { $0 = true }
        // Simulate an uncooperative host operation completing after cancellation.
        await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
        finished.withLock { $0 = true }
        return [42]
    })
    let host = try HostRegistration(signer: signer, transport: CloudTransport(open: { _ in CloudStream(items: []) }))
    defer { host.close() }
    let client = CloudClient(host: host, authority: authority)
    let task = Task { try await client.cloudDevices(organizationID: tenant, accessToken: "test-token") }
    try await eventually { started.withLock { $0 } }
    task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    try await eventually { finished.withLock { $0 } }
}

private struct BrokenEntropy: Entropy {
    let fails: Bool
    func randomBytes(count: Int) async throws -> [UInt8] {
        struct PrivateError: Error { let secret = "do-not-expose" }
        if fails { throw PrivateError() }
        return []
    }
}

@Test(arguments: [true, false])
func `invalid host entropy fails without leaking private diagnostics`(fails: Bool) async throws {
    let host = try HostRegistration(signer: CloudSigner(), transport: CloudTransport(open: { _ in
        Issue.record("Invalid entropy must fail before network I/O")
        return CloudStream(items: [])
    }), entropy: BrokenEntropy(fails: fails))
    defer { host.close() }
    do {
        _ = try await CloudClient(host: host, authority: authority).cloudDevices(organizationID: tenant, accessToken: "test-token")
        Issue.record("Expected entropy failure")
    } catch let error as RPCStatusError {
        #expect(error.code == 13)
        #expect(!error.message.contains("do-not-expose"))
    }
}
