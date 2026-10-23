/// An enrollment failure with a stable code and its original cause.
///
/// Messages contain only SDK-owned text. Original causes are retained separately
/// for app diagnostics and must be redacted before display or logging. Host
/// capabilities must never put EAB keys or credential-bearing payloads in errors.
public struct DeviceEnrollmentError: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// An extensible classification of enrollment failures.
    public struct Code: Hashable, Sendable, CustomStringConvertible {
        /// A diagnostic identifier for the failure category.
        public let description: String

        /// The SDK operation is still a stub.
        public static let notImplemented = Self(
            description: "notImplemented",
            message: "This SDK operation has not been implemented."
        )

        /// The name does not satisfy the device label rules.
        public static let invalidName = Self(
            description: "invalidName",
            message: "The device name is invalid."
        )

        /// The requested organization differs from the operator certificate tenant.
        public static let organizationMismatch = Self(
            description: "organizationMismatch",
            message: "The operator identity belongs to a different organization."
        )

        /// The agent already has an enrolled identity.
        public static let alreadyEnrolled = Self(
            description: "alreadyEnrolled",
            message: "The device is already enrolled."
        )

        /// The agent lacks a required enrollment capability.
        public static let agentOutdated = Self(
            description: "agentOutdated",
            message: "The agent must be updated before enrollment."
        )

        /// The device cannot perform the required enrollment flow.
        public static let unsupported = Self(
            description: "unsupported",
            message: "This device does not support enrollment."
        )

        /// A pending reset prevents enrollment.
        public static let resetPending = Self(
            description: "resetPending",
            message: "The device must finish resetting before enrollment."
        )

        /// The signer cannot produce the required operator proof.
        public static let signerUnsupported = Self(
            description: "signerUnsupported",
            message: "The operator signer does not support the required algorithm."
        )

        /// The caller lacks authority to enroll the device.
        public static let permissionDenied = Self(
            description: "permissionDenied",
            message: "Enrollment was not authorized."
        )

        /// The requested name is reserved within the organization.
        public static let nameUnavailable = Self(
            description: "nameUnavailable",
            message: "The device name is already in use."
        )

        /// Cloud refused the request as malformed or inconsistent.
        public static let invalidRequest = Self(
            description: "invalidRequest",
            message: "The enrollment request was refused as invalid."
        )

        /// Cloud does not implement the required enrollment RPC.
        public static let cloudUnsupported = Self(
            description: "cloudUnsupported",
            message: "Cloud does not support this enrollment operation."
        )

        /// Cloud is unavailable before a reservation outcome is known.
        public static let cloudUnavailable = Self(
            description: "cloudUnavailable",
            message: "Cloud could not be reached for enrollment."
        )

        /// Device or mesh identifier collisions exhausted the retry limit.
        public static let deviceIDCollisions = Self(
            description: "deviceIDCollisions",
            message: "A unique device identity could not be reserved."
        )

        /// The returned credential is incomplete or has an unexpected kind.
        public static let invalidCredential = Self(
            description: "invalidCredential",
            message: "Cloud returned an invalid enrollment credential."
        )

        /// Agent provisioning failed after Cloud reserved the device.
        public static let deviceFailed = Self(
            description: "deviceFailed",
            message: "The device could not complete enrollment."
        )

        /// The agent returned a principal that differs from the reserved identity.
        public static let identityMismatch = Self(
            description: "identityMismatch",
            message: "The device returned an unexpected enrollment identity."
        )

        /// The request may have reserved or enrolled the device before contact was lost.
        public static let outcomeUnknown = Self(
            description: "outcomeUnknown",
            message: "The enrollment outcome could not be confirmed."
        )

        fileprivate let message: String

        private init(description: String, message: String) {
            self.description = description
            self.message = message
        }
    }

    /// A device identity that Cloud has reserved, or may have reserved after a lost response.
    ///
    /// No one-time enrollment credential is exposed. Confirm the Cloud state and
    /// remove any reservation before attempting a fresh enrollment.
    public struct Reservation: Sendable, Hashable {
        /// The attempted permanent device identifier.
        public var id: DeviceID

        /// The name used in the reservation request.
        public var name: DeviceName

        /// Creates reservation details without performing any Cloud operation.
        public init(id: DeviceID, name: DeviceName) {
            self.id = id
            self.name = name
        }
    }

    /// The stable classification used for programmatic handling.
    public let code: Code

    /// A credential-free explanation derived solely from the failure code.
    public var message: String { code.message }

    /// The original failure, preserving its type, status and cause chain.
    ///
    /// This is diagnostic data, not safe display text. Redact it before presentation.
    public let underlyingError: any Error

    /// Details of a known or possible Cloud reservation, if the request reached Cloud.
    public let reservation: Reservation?

    /// The failure code and SDK message, without the cause or reservation values.
    public var description: String { "\(code): \(message)" }

    /// The failure code and SDK message, without the cause or reservation values.
    public var debugDescription: String { description }

    /// Creates a failure while requiring and preserving its original cause.
    ///
    /// The message cannot accept arbitrary text or credential values. For failures
    /// originating in the SDK, the underlying error will describe that local failure.
    public init(code: Code, underlyingError: any Error, reservation: Reservation? = nil) {
        self.code = code
        self.underlyingError = underlyingError
        self.reservation = reservation
    }

    static func notImplemented(operation: String) -> Self {
        Self(code: .notImplemented, underlyingError: UnimplementedOperation(operation: operation))
    }
}

private struct UnimplementedOperation: Error, CustomStringConvertible {
    let operation: String
    var description: String { "\(operation) has not been implemented." }
}
