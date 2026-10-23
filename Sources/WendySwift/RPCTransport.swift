#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Sends unary protobuf RPCs through an app-owned transport.
///
/// The app owns connection security and Cloud OAuth/DPoP. Implementations must not
/// log request or response bodies: enrollment exchanges a one-time EAB credential.
public protocol RPCTransport: Sendable {
    /// Sends one request and returns its successful response.
    ///
    /// Throws `RPCStatusError` for a non-OK gRPC status. Local transport failures may
    /// retain their native error type. Honor the timeout and task cancellation,
    /// preserve response trailers, and do not retry enrollment requests automatically.
    /// Error causes must exclude credential bytes and credential-bearing payloads.
    func unary(_ request: RPCRequest) async throws -> RPCResponse
}

/// A serialized unary protobuf request for the app's transport.
public struct RPCRequest: Sendable {
    /// The fully qualified `package.Service/Method` name, without a leading slash.
    public var method: String

    /// The serialized protobuf message, which may contain credentials and must not be logged.
    public var message: Data

    /// Additional request metadata, before the app adds authentication.
    public var metadata: RPCMetadata

    /// The maximum call duration, or nil to use the transport's default.
    public var timeout: Duration?

    /// Creates request data without sending or validating it.
    public init(
        method: String,
        message: Data,
        metadata: RPCMetadata = .init(entries: []),
        timeout: Duration? = nil
    ) {
        self.method = method
        self.message = message
        self.metadata = metadata
        self.timeout = timeout
    }
}

/// A successful unary protobuf response, including its headers and trailers.
public struct RPCResponse: Sendable {
    /// The serialized protobuf message, which may contain a one-time enrollment credential.
    public var message: Data

    /// The response's initial metadata.
    public var initialMetadata: RPCMetadata

    /// The response's trailing metadata.
    public var trailingMetadata: RPCMetadata

    /// Creates response data without decoding or validating it.
    public init(
        message: Data,
        initialMetadata: RPCMetadata = .init(entries: []),
        trailingMetadata: RPCMetadata = .init(entries: [])
    ) {
        self.message = message
        self.initialMetadata = initialMetadata
        self.trailingMetadata = trailingMetadata
    }
}

/// Ordered RPC metadata that preserves repeated names and binary values.
///
/// Names compare case-insensitively at the transport boundary. This value stores
/// entries exactly as supplied; adapters handle gRPC name and value validation.
public struct RPCMetadata: Sendable, Hashable {
    /// One metadata name and value, without logging or display formatting.
    public struct Entry: Sendable, Hashable {
        /// The metadata name; binary values use the gRPC `-bin` suffix.
        public var name: String

        /// ASCII bytes for ordinary metadata, or decoded bytes for binary metadata.
        public var value: Data

        /// Creates one entry without normalizing or validating its contents.
        public init(name: String, value: Data) {
            self.name = name
            self.value = value
        }
    }

    /// The entries in their original order, including repeated names.
    public var entries: [Entry]

    /// Creates metadata from ordered entries without combining repeated names.
    public init(entries: [Entry]) {
        self.entries = entries
    }
}

/// A non-OK RPC status with the original failure and response metadata.
///
/// The cause is retained for app diagnostics, but never interpolated into the SDK's
/// message or debug description. The app must redact causes before displaying or
/// logging them; transports must never put enrollment credential bytes in errors.
public struct RPCStatusError: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The gRPC status reported by the transport.
    public let code: RPCStatusCode

    /// The original transport error, including its diagnostic text and cause chain.
    public let underlyingError: any Error

    /// The response's initial metadata.
    public let initialMetadata: RPCMetadata

    /// The response's trailing metadata, including collision details when present.
    public let trailingMetadata: RPCMetadata

    /// A credential-free status message; detailed diagnostics are in the original error.
    public var message: String { "RPC failed with status \(code.rawValue)." }

    /// The status message, excluding the original error and metadata.
    public var description: String { message }

    /// The status message, excluding the original error and metadata.
    public var debugDescription: String { description }

    /// Creates a status failure while requiring and preserving its original cause.
    public init(
        code: RPCStatusCode,
        underlyingError: any Error,
        initialMetadata: RPCMetadata = .init(entries: []),
        trailingMetadata: RPCMetadata = .init(entries: [])
    ) {
        self.code = code
        self.underlyingError = underlyingError
        self.initialMetadata = initialMetadata
        self.trailingMetadata = trailingMetadata
    }
}

/// An extensible numeric gRPC status code.
public struct RPCStatusCode: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    /// The numeric gRPC wire value.
    public let rawValue: Int

    /// The wire value as text.
    public var description: String { String(rawValue) }

    /// Creates a status code, preserving unknown wire values for future compatibility.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The RPC completed successfully.
    public static let ok = Self(rawValue: 0)
    /// The RPC was cancelled.
    public static let cancelled = Self(rawValue: 1)
    /// The failure could not be classified.
    public static let unknown = Self(rawValue: 2)
    /// An argument was invalid.
    public static let invalidArgument = Self(rawValue: 3)
    /// The call deadline expired.
    public static let deadlineExceeded = Self(rawValue: 4)
    /// The requested resource was not found.
    public static let notFound = Self(rawValue: 5)
    /// The resource already exists.
    public static let alreadyExists = Self(rawValue: 6)
    /// The caller lacks permission.
    public static let permissionDenied = Self(rawValue: 7)
    /// A resource limit was exhausted.
    public static let resourceExhausted = Self(rawValue: 8)
    /// The current state prevents the operation.
    public static let failedPrecondition = Self(rawValue: 9)
    /// The operation was aborted.
    public static let aborted = Self(rawValue: 10)
    /// An argument exceeded the supported range.
    public static let outOfRange = Self(rawValue: 11)
    /// The server does not implement the operation.
    public static let unimplemented = Self(rawValue: 12)
    /// The server encountered an internal error.
    public static let internalError = Self(rawValue: 13)
    /// The service is temporarily unavailable.
    public static let unavailable = Self(rawValue: 14)
    /// Data was lost or corrupted.
    public static let dataLoss = Self(rawValue: 15)
    /// The caller is not authenticated.
    public static let unauthenticated = Self(rawValue: 16)
}
