/// A host-owned signing key. Implementations must support concurrent calls,
/// honor task cancellation and never expose private keys or secrets in errors.
public protocol Signer: Sendable {
    /// Protocol name, for example `ML-DSA-65`. Fixed for this key's lifetime.
    var algorithm: String { get }
    /// Leaf-first DER certificates, or empty if publicKey supplies the identity.
    func certificateChain() async throws -> [[UInt8]]
    /// DER SubjectPublicKeyInfo, or empty if certificateChain supplies it.
    func publicKey() async throws -> [UInt8]
    /// Sign exactly these bytes, without additional encoding or pre-hashing.
    func sign(_ message: [UInt8]) async throws -> [UInt8]
}

/// One metadata value; order, repeated names and raw binary values are preserved.
public struct RPCMetadataEntry: Sendable, Equatable {
    public var name: String
    public var value: [UInt8]

    public init(name: String, value: [UInt8]) { self.name = name; self.value = value }
}

/// A serialized protobuf call. The host validates metadata and supplies TLS/auth.
public struct RPCRequest: Sendable, Equatable {
    public var method: String
    public var message: [UInt8]
    public var metadata: [RPCMetadataEntry]
    /// Absolute UTC Unix milliseconds; nil means no Core deadline.
    public var deadlineUnixMilliseconds: Int64?

    public init(method: String, message: [UInt8], metadata: [RPCMetadataEntry] = [], deadlineUnixMilliseconds: Int64? = nil) {
        self.method = method
        self.message = message
        self.metadata = metadata
        self.deadlineUnixMilliseconds = deadlineUnixMilliseconds
    }
}

public struct RPCResponse: Sendable, Equatable {
    public var message: [UInt8]
    public var initialMetadata: [RPCMetadataEntry]
    public var trailingMetadata: [RPCMetadataEntry]

    public init(message: [UInt8], initialMetadata: [RPCMetadataEntry] = [], trailingMetadata: [RPCMetadataEntry] = []) {
        self.message = message
        self.initialMetadata = initialMetadata
        self.trailingMetadata = trailingMetadata
    }
}

/// Original numeric gRPC status, diagnostic and metadata, including unknown codes.
/// Diagnostics must never contain credentials or private key material.
public struct RPCStatusError: Error, Sendable, Equatable, CustomStringConvertible {
    public var description: String { "RPC failed with status \(code)" }
    public let code: UInt32
    public var message: String
    public var initialMetadata: [RPCMetadataEntry]
    public var trailingMetadata: [RPCMetadataEntry]

    public init(code: UInt32, message: String, initialMetadata: [RPCMetadataEntry] = [], trailingMetadata: [RPCMetadataEntry] = []) {
        precondition(code != 0, "An RPC error requires a non-OK status")
        self.code = code
        self.message = message
        self.initialMetadata = initialMetadata
        self.trailingMetadata = trailingMetadata
    }
}

/// Host-owned networking. Calls honor task cancellation and the request deadline.
/// Do not automatically retry application RPCs or log request/response payloads.
public protocol Transport: Sendable {
    func unary(_ request: RPCRequest) async throws -> RPCResponse
    func serverStream(_ request: RPCRequest) async throws -> any ServerStream
}

/// Demand-driven serialized messages. Core calls next once per requested item,
/// serially with headers/trailers. nil ends successfully; throw RPCStatusError
/// for a remote failure. Implementations must unblock promptly on cancellation.
/// An actor is a suitable implementation. Avoid an unbounded prefetch queue.
public protocol ServerStream: Sendable {
    func initialMetadata() async throws -> [RPCMetadataEntry]
    func next() async throws -> [UInt8]?
    func trailingMetadata() async throws -> [RPCMetadataEntry]
    /// Idempotently release stream resources, including after success or error.
    /// May run on any executor. The binding calls this when the stream finishes.
    func close()
}
