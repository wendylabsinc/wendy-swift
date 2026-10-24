internal import CWendyCore
internal import Foundation
internal import SwiftProtobuf
internal import Synchronization

/// The published Cloud v2 Asset, including optional and unknown protobuf fields.
public typealias CloudDevice = Wendycloud_V2_Asset

/// Thin access to Core's Cloud client. The host owns its TLS connection, key and
/// token lifecycle. Its transport must be bound to authority, and the host must
/// validate the ML-DSA-65 key and its tenant/token binding before calling Core.
public struct CloudClient: Sendable {
    public init(host: HostRegistration, authority: String) {
        self.host = host
        self.authority = authority
    }

    /// Returns the complete bounded inventory or throws, without partial results.
    /// organizationID is the immutable tenant UUID, never a realm/organization
    /// slug. accessToken must be DPoP-bound to the host key. Core builds proofs
    /// and handles the service's pagination; no retry or refresh is added here.
    /// Cancellation throws CancellationError; other failures preserve numeric
    /// gRPC status and metadata in RPCStatusError (deadline exceeded is code 4).
    /// Remote diagnostics and metadata are untrusted and may contain secrets.
    public func cloudDevices(
        organizationID: String, accessToken: String, filter: String = "",
        onlineOnly: Bool = false, deadlineUnixMilliseconds: Int64? = nil
    ) async throws -> [CloudDevice] {
        try Task.checkCancellation()
        var request = Wendy_Core_V1_CloudDeviceListRequest()
        request.authority = authority
        request.organizationID = organizationID
        request.accessToken = accessToken
        request.filter = filter
        request.onlineOnly = onlineOnly
        request.deadlineUnixMillis = deadlineUnixMilliseconds ?? 0
        let bytes: [UInt8] = try request.serializedBytes()
        let response = try await CloudOperation(host: host).run(bytes)
        let envelope = try Wendy_Core_V1_CloudDeviceListResponse(serializedBytes: response)
        return try envelope.assets.map { try CloudDevice(serializedBytes: $0) }
    }

    private let host: HostRegistration
    private let authority: String
}

/// Serializes pointer use/release and cancellation. The callback owns a retained
/// Swift context until delivery, and the operation keeps the host alive. No raw
/// pointer escapes the lock or crosses an await. Start never waits for callbacks.
private final class CloudOperation: Sendable {
    private struct State {
        var operation: OpaquePointer?
        var cancelled = false
        var continuation: CheckedContinuation<[UInt8], any Error>?
    }
    private let state = Mutex(State())
    private let host: HostRegistration

    init(host: HostRegistration) { self.host = host }

    func run(_ bytes: [UInt8]) async throws -> [UInt8] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { state in
                    state.continuation = continuation
                    let context = Unmanaged.passRetained(self)
                    state.operation = bytes.withUnsafeBufferPointer { buffer in
                        WendyCloudListDevicesCreate(
                            host.handle, WendyDataView(data: buffer.baseAddress, size: buffer.count),
                            { context, response, error in
                                guard let context else { return }
                                let operation = Unmanaged<CloudOperation>.fromOpaque(context).takeRetainedValue()
                                operation.complete(response: response, error: error)
                            }, context.toOpaque())
                    }
                    guard let operation = state.operation else {
                        context.release() // Create failed: Core owns no context.
                        state.continuation = nil
                        continuation.resume(throwing: RPCStatusError(code: 13, message: "Core could not create the Cloud operation"))
                        return
                    }
                    if state.cancelled { WendyOperationCancel(operation) }
                    // Store the handle before activation: completion may race
                    // Start's return, but cannot precede Create's return.
                    WendyOperationStart(operation)
                }
            }
        } onCancel: {
            self.state.withLock { state in
                state.cancelled = true
                if let operation = state.operation { WendyOperationCancel(operation) }
            }
        }
    }

    private func complete(response: OpaquePointer?, error: OpaquePointer?) {
        defer {
            WendyDataRelease(response)
            WendyErrorRelease(error)
        }
        let result: Result<[UInt8], any Error>
        do {
            if let error {
                let code = WendyErrorGetCode(error)
                if code == 1 {
                    result = .failure(CancellationError())
                } else {
                    let details = try Wendy_Core_V1_RPCErrorDetails(serializedBytes: copy(WendyErrorGetDetails(error)))
                    result = .failure(RPCStatusError(
                        code: code, message: String(decoding: copy(WendyErrorGetMessage(error)), as: UTF8.self),
                        initialMetadata: details.initialMetadata.map { RPCMetadataEntry(name: $0.name, value: Array($0.value)) },
                        trailingMetadata: details.trailingMetadata.map { RPCMetadataEntry(name: $0.name, value: Array($0.value)) }))
                }
            } else if let response {
                result = .success(copy(WendyDataGetBytes(response)))
            } else {
                result = .failure(RPCStatusError(code: 13, message: "Core returned no Cloud result"))
            }
        } catch {
            result = .failure(error)
        }
        let continuation = state.withLock { state in
            if let operation = state.operation { WendyOperationRelease(operation) }
            state.operation = nil
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private func copy(_ view: WendyDataView) -> [UInt8] {
    Array(UnsafeBufferPointer(start: view.data, count: view.size))
}
