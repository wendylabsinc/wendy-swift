internal import CWendyCore
internal import Synchronization

/// Registers host signing and networking with the linked Core engine.
/// Keep alive for the Core operations using it. close cancels outstanding work;
/// deinitialization closes automatically. This module links Go into the process
/// and belongs in the app, never in its network extension.
public final class HostRegistration: Sendable {
    /// Opaque process-local Core registration, for Core operations accepting a host.
    /// It is invalid after close. Never persist or transfer between processes.
    public let handle: UInt64

    public init(signer: any Signer, transport: any Transport, entropy: any Entropy = SystemEntropy()) throws {
        let algorithm = signer.algorithm
        guard !algorithm.isEmpty else { throw HostRegistrationError.emptyAlgorithm }
        let context = Unmanaged.passRetained(HostContext(signer: signer, transport: transport, entropy: entropy))
        let arena = HostArena()
        var callbacks = WendyHostCallbacks(
            context: context.toOpaque(), algorithm: arena.bytes(Array(algorithm.utf8)),
            start: { context, call, request in
                guard let context, let request else { return }
                // All borrowed request views are copied before this callback returns.
                Unmanaged<HostContext>.fromOpaque(context).takeUnretainedValue().start(call, request.pointee)
            },
            request_next: { context, call in
                guard let context else { return }
                Unmanaged<HostContext>.fromOpaque(context).takeUnretainedValue().demand(call)
            },
            cancel: { context, call in
                guard let context else { return }
                Unmanaged<HostContext>.fromOpaque(context).takeUnretainedValue().cancel(call)
            },
            release: { context in
                guard let context else { return }
                Unmanaged<HostContext>.fromOpaque(context).release()
            })
        handle = WendyHostCreate(&callbacks)
        guard handle != 0 else {
            context.release() // Create transfers ownership only on success.
            throw HostRegistrationError.rejected
        }
    }

    public func close() { WendyHostRelease(handle) }
    deinit { WendyHostRelease(handle) }
}

public enum HostRegistrationError: Error { case emptyAlgorithm, rejected }

private struct HostCall: Sendable {
    let task: Task<Void, Never>
    let demand: AsyncStream<Void>.Continuation
}

private final class HostContext: Sendable {
    let signer: any Signer
    let transport: any Transport
    let entropy: any Entropy
    let calls = Mutex<[UInt64: HostCall]>([:])

    init(signer: any Signer, transport: any Transport, entropy: any Entropy) {
        self.signer = signer
        self.transport = transport
        self.entropy = entropy
    }

    func start(_ call: UInt64, _ input: WendyHostRequest) {
        let operation = input.operation
        let request = RPCRequest(method: String(decoding: copyBytes(input.method), as: UTF8.self),
                                 message: copyBytes(input.message), metadata: copyMetadata(input.metadata),
                                 deadlineUnixMilliseconds: input.deadline_unix_millis == 0 ? nil : input.deadline_unix_millis)
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Publish the task while holding the lock so completion/cancel cannot
        // remove it before insertion. C callbacks never wait for task execution.
        calls.withLock { calls in
            let task = Task {
                do {
                    switch operation {
                    case UInt32(WendyHostSign):
                        complete(call, response: RPCResponse(message: try await signer.sign(request.message)))
                    case UInt32(WendyHostCertificateChain):
                        complete(call, certificates: try await signer.certificateChain())
                    case UInt32(WendyHostPublicKey):
                        complete(call, response: RPCResponse(message: try await signer.publicKey()))
                    case UInt32(WendyHostRandomBytes):
                        guard request.message.count == 4 else {
                            throw RPCStatusError(code: 3, message: "Invalid entropy byte count")
                        }
                        let count = request.message.reduce(0) { ($0 << 8) | Int($1) }
                        guard (1...1_048_576).contains(count) else {
                            throw RPCStatusError(code: 3, message: "Invalid entropy byte count")
                        }
                        let bytes = try await entropy.randomBytes(count: count)
                        guard bytes.count == count else {
                            throw RPCStatusError(code: 13, message: "Invalid entropy response length")
                        }
                        complete(call, response: RPCResponse(message: bytes))
                    case UInt32(WendyHostUnary):
                        complete(call, response: try await transport.unary(request))
                    case UInt32(WendyHostServerStream):
                        let source = try await transport.serverStream(request)
                        defer { source.close() }
                        let headers = try await source.initialMetadata()
                        let arena = HostArena()
                        guard WendyHostStreamHeader(call, arena.metadata(headers)) != 0 else { break }
                        for await _ in stream {
                            try Task.checkCancellation()
                            guard let message = try await source.next() else {
                                complete(call, response: RPCResponse(message: [], trailingMetadata: try await source.trailingMetadata()))
                                break
                            }
                            let item = HostArena()
                            guard WendyHostStreamMessage(call, item.bytes(message)) != 0 else { break }
                        }
                    default:
                        throw RPCStatusError(code: 12, message: "Unsupported host operation")
                    }
                } catch {
                    complete(call, error: error)
                }
                finish(call)
            }
            calls[call] = HostCall(task: task, demand: continuation)
        }
    }

    func demand(_ call: UInt64) {
        let continuation = calls.withLock { $0[call]?.demand }
        continuation?.yield(())
    }

    func cancel(_ call: UInt64) {
        let work = calls.withLock { $0.removeValue(forKey: call) }
        work?.demand.finish()
        work?.task.cancel()
    }

    func finish(_ call: UInt64) {
        calls.withLock { $0.removeValue(forKey: call) }?.demand.finish()
    }
}

private func complete(_ call: UInt64, response: RPCResponse = RPCResponse(message: []), certificates: [[UInt8]] = [], error: (any Error)? = nil) {
    let arena = HostArena()
    // Preserve explicit remote diagnostics. Arbitrary host errors may contain
    // credentials: expose a fixed local diagnostic across the boundary.
    let status = error.map { error in
        (error as? RPCStatusError) ?? RPCStatusError(
            code: error is CancellationError ? 1 : 13,
            message: error is CancellationError ? "Host call cancelled" : "Host capability failed")
    }
    var result = WendyHostResult(
        code: status?.code ?? 0, status_message: arena.bytes(Array((status?.message ?? "").utf8)),
        message: arena.bytes(status == nil ? response.message : []),
        certificates: arena.array(certificates.map { arena.bytes($0) }), certificate_count: certificates.count,
        initial_metadata: arena.metadata(status?.initialMetadata ?? response.initialMetadata),
        trailing_metadata: arena.metadata(status?.trailingMetadata ?? response.trailingMetadata))
    WendyHostComplete(call, &result)
}

private func copyBytes(_ view: WendyHostBytes) -> [UInt8] {
    Array(UnsafeBufferPointer(start: view.data, count: view.size))
}

private func copyMetadata(_ metadata: WendyHostMetadata) -> [RPCMetadataEntry] {
    UnsafeBufferPointer(start: metadata.entries, count: metadata.count).map {
        RPCMetadataEntry(name: String(decoding: copyBytes($0.name), as: UTF8.self), value: copyBytes($0.value))
    }
}

/// Owns only synchronous C-call arguments. Never crosses an await or callback.
private final class HostArena {
    private var cleanup: [() -> Void] = []

    func array<T>(_ values: [T]) -> UnsafePointer<T>? {
        guard !values.isEmpty else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: values.count)
        pointer.initialize(from: values, count: values.count)
        cleanup.append { pointer.deinitialize(count: values.count); pointer.deallocate() }
        return UnsafePointer(pointer)
    }

    func bytes(_ bytes: [UInt8]) -> WendyHostBytes { WendyHostBytes(data: array(bytes), size: bytes.count) }
    func metadata(_ entries: [RPCMetadataEntry]) -> WendyHostMetadata {
        WendyHostMetadata(entries: array(entries.map {
            WendyHostMetadataEntry(name: bytes(Array($0.name.utf8)), value: bytes($0.value))
        }), count: entries.count)
    }
    deinit { for free in cleanup.reversed() { free() } }
}
