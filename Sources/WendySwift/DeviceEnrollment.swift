#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Enrolls nearby WendyOS devices in an organization.
///
/// The app owns discovery, consent, operator key custody and authenticated transports.
public struct DeviceEnrollment: Sendable {
    /// The endpoints and audience used for device enrollment.
    public struct Configuration: Sendable, Hashable {
        /// The Cloud endpoint the enrolled device connects to, as `host:port`.
        public var cloudEndpoint: String

        /// The ACME service's base URL, before the organization's directory path.
        public var certificateAuthority: URL

        /// The audience of signed Cloud requests, such as `https://cloud.wendy.sh/broker`.
        public var requestAudience: String

        /// Creates configuration values without validating or contacting the endpoints.
        public init(cloudEndpoint: String, certificateAuthority: URL, requestAudience: String) {
            self.cloudEndpoint = cloudEndpoint
            self.certificateAuthority = certificateAuthority
            self.requestAudience = requestAudience
        }
    }

    /// Creates an enrollment client using the app's Cloud transport and operator signer.
    ///
    /// Only stores these capabilities; it performs no validation, signing or I/O.
    /// The Cloud transport attaches OAuth and DPoP credentials as needed.
    public init(configuration: Configuration, cloud: some RPCTransport, signer: some OperatorSigner) {
        self.configuration = configuration
        self.cloud = cloud
        self.signer = signer
    }

    /// Checks whether the device reached by the transport can enroll, without changing it.
    ///
    /// Checks the agent's provisioning state and ACME capability before any
    /// Cloud reservation.
    public func readiness(of device: some RPCTransport) async throws -> EnrollmentReadiness {
        throw DeviceEnrollmentError.notImplemented(operation: "DeviceEnrollment.readiness(of:)")
    }

    /// Enrolls the device reached by the transport under a name in the organization.
    ///
    /// Checks readiness and the operator's organization, reads hardware best-effort,
    /// requests a class B credential, provisions the agent and verifies its principal.
    /// The app must obtain consent before calling. A failure after Cloud reserves the
    /// device carries reservation details; the app must confirm the Cloud state and
    /// arrange removal of any reservation before retrying.
    public func enroll(
        _ device: some RPCTransport,
        named name: DeviceName,
        in organization: OrganizationID
    ) async throws -> EnrolledDevice {
        throw DeviceEnrollmentError.notImplemented(operation: "DeviceEnrollment.enroll(_:named:in:)")
    }

    private let configuration: Configuration
    private let cloud: any RPCTransport
    private let signer: any OperatorSigner
}

/// A device's organization-unique DNS label.
public struct DeviceName: Hashable, Sendable, CustomStringConvertible {
    /// The validated label.
    public let rawValue: String

    /// The label as text.
    public var description: String { rawValue }

    /// Validates a device name and creates its value.
    ///
    /// Requires `^[a-z][a-z0-9-]{0,62}$` without a trailing hyphen and throws
    /// `DeviceEnrollmentError` with code `.invalidName` otherwise.
    public init(_ name: String) throws(DeviceEnrollmentError) {
        throw DeviceEnrollmentError.notImplemented(operation: "DeviceName.init(_:)")
    }

    /// Suggests a valid name from a host name, or returns nil when none fits.
    ///
    /// Lowercases the host and removes its `.local` suffix, following the CLI.
    public static func suggested(forHost host: String) throws(DeviceEnrollmentError) -> DeviceName? {
        throw DeviceEnrollmentError.notImplemented(operation: "DeviceName.suggested(forHost:)")
    }

    // Internal construction permits value fixtures without exposing a validation bypass.
    init(unchecked name: String) {
        self.rawValue = name
    }
}

/// An organization's immutable tenant UUID.
public struct OrganizationID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The tenant UUID, rather than its reclaimable realm slug.
    public var uuid: UUID

    /// The UUID as text.
    public var description: String { uuid.uuidString }

    /// Creates an organization identifier from its UUID.
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }
}

/// A device's permanent UUID, also used as its Cloud asset identifier.
public struct DeviceID: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The permanent device UUID.
    public var uuid: UUID

    /// The UUID as text.
    public var description: String { uuid.uuidString }

    /// Creates a device identifier from its UUID.
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }
}

/// The identity returned after enrollment completes.
public struct EnrolledDevice: Sendable, Hashable {
    /// The permanent device identifier.
    public var id: DeviceID

    /// The device's name within the organization.
    public var name: DeviceName

    /// The organization that owns the enrolled device.
    public var organization: OrganizationID

    /// The certificate principal, `spiffe://wendy.sh/tenant/<organization>/device/<id>`.
    public var principal: String

    /// Creates a result value without verifying its identity or enrolling a device.
    public init(id: DeviceID, name: DeviceName, organization: OrganizationID, principal: String) {
        self.id = id
        self.name = name
        self.organization = organization
        self.principal = principal
    }
}

/// A snapshot of an agent's ability to enroll.
public struct EnrollmentReadiness: Sendable, Hashable {
    /// An extensible reason an agent cannot enroll.
    public struct Obstacle: Hashable, Sendable, CustomStringConvertible {
        /// The agent already has an enrolled identity.
        public static let alreadyEnrolled = Self(description: "alreadyEnrolled")

        /// The agent lacks the readiness RPC or ACME capability information.
        public static let agentOutdated = Self(description: "agentOutdated")

        /// The agent reports that enrollment is unavailable on this device.
        public static let unsupported = Self(description: "unsupported")

        /// The agent must finish resetting before it can enroll.
        public static let resetPending = Self(description: "resetPending")

        /// A diagnostic identifier for the obstacle.
        public let description: String

        private init(description: String) {
            self.description = description
        }
    }

    /// The obstacle preventing enrollment, or nil when the agent is ready.
    public var obstacle: Obstacle?

    /// The agent's explanation, if any; this is untrusted text, not an error code.
    public var reason: String?

    /// Whether this snapshot contains no obstacle to enrollment.
    public var isReady: Bool { obstacle == nil }

    /// Creates a readiness snapshot without contacting an agent.
    public init(obstacle: Obstacle?, reason: String? = nil) {
        self.obstacle = obstacle
        self.reason = reason
    }
}
