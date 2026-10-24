#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import WendySwift

@Test
func `constructs enrollment values without performing enrollment`() throws {
    let organization = OrganizationID(UUID())
    let id = DeviceID(UUID())
    let name = DeviceName(unchecked: "workbench")
    let principal = "spiffe://wendy.sh/tenant/\(organization)/device/\(id)"
    let result = EnrolledDevice(id: id, name: name, organization: organization, principal: principal)
    let reservation = DeviceEnrollmentError.Reservation(id: id, name: name)
    let configuration = try configuration()

    #expect(configuration.cloudEndpoint == "api.example.test:443")
    #expect(configuration.certificateAuthority.absoluteString == "https://acme.example.test")
    #expect(configuration.requestAudience == "https://cloud.example.test/broker")
    #expect(result.id == id)
    #expect(result.name.rawValue == "workbench")
    #expect(result.name.description == "workbench")
    #expect(result.organization == organization)
    #expect(result.principal == principal)
    #expect(reservation.id == id)
    #expect(reservation.name == name)
    #expect(organization.uuid.uuidString == organization.description)
    #expect(id.uuid.uuidString == id.description)
    #expect(try JSONDecoder().decode(OrganizationID.self, from: JSONEncoder().encode(organization)) == organization)
    #expect(try JSONDecoder().decode(DeviceID.self, from: JSONEncoder().encode(id)) == id)
}

@Test
func `constructs readiness snapshots for every proposed obstacle`() {
    #expect(EnrollmentReadiness(obstacle: nil).isReady)
    let obstacles: [EnrollmentReadiness.Obstacle] = [
        .alreadyEnrolled, .agentOutdated, .unsupported, .resetPending,
    ]
    #expect(Set(obstacles).count == obstacles.count)
    for obstacle in obstacles {
        let readiness = EnrollmentReadiness(obstacle: obstacle, reason: "Agent explanation.")
        #expect(!readiness.isReady)
        #expect(readiness.obstacle == obstacle)
        #expect(readiness.reason == "Agent explanation.")
        #expect(!obstacle.description.isEmpty)
    }
}

@Test(arguments: ["workbench", "", "INVALID", "trailing-", "credential-canary"])
func `name validation is a throwing stub for every input`(input: String) {
    #expect {
        try DeviceName(input)
    } throws: { error in
        isUnimplemented(error, operation: "DeviceName.init(_:)")
    }
}

@Test(arguments: ["Workbench.local", "", "invalid.host", "credential-canary"])
func `name suggestion is a throwing stub for every input`(input: String) {
    #expect {
        try DeviceName.suggested(forHost: input)
    } throws: { error in
        isUnimplemented(error, operation: "DeviceName.suggested(forHost:)")
    }
}

@Test
func `readiness throws without calling either transport or the signer`() async throws {
    let cloud = HostProbe()
    let device = HostProbe()
    let signer = HostProbe()
    let enrollment = try DeviceEnrollment(configuration: configuration(), cloud: cloud, signer: signer)
    await #expect {
        try await enrollment.readiness(of: device)
    } throws: { error in
        isUnimplemented(error, operation: "DeviceEnrollment.readiness(of:)")
    }
    #expect(await cloud.calls == 0)
    #expect(await device.calls == 0)
    #expect(await signer.calls == 0)
}

@Test
func `enrollment throws without reserving a device or using host capabilities`() async throws {
    let cloud = HostProbe()
    let device = HostProbe()
    let signer = HostProbe()
    let enrollment = try DeviceEnrollment(configuration: configuration(), cloud: cloud, signer: signer)
    await #expect {
        try await enrollment.enroll(
            device, named: DeviceName(unchecked: "workbench"), in: OrganizationID(UUID())
        )
    } throws: { error in
        isUnimplemented(error, operation: "DeviceEnrollment.enroll(_:named:in:)")
    }
    #expect(await cloud.calls == 0)
    #expect(await device.calls == 0)
    #expect(await signer.calls == 0)
}

@Test
func `metadata preserves duplicate names binary values and header trailer separation`() {
    let entries: [RPCMetadata.Entry] = [
        .init(name: "X-Example", value: Data("first".utf8)),
        .init(name: "x-example", value: Data("second".utf8)),
        .init(name: "details-bin", value: Data([0, 255, 128])),
    ]
    let headers = RPCMetadata(entries: entries)
    let trailers = RPCMetadata(entries: [
        .init(name: "wendy-colliding-field", value: Data("device_id".utf8))
    ])
    let request = RPCRequest(
        method: "example.Service/Method", message: Data([1, 2]), metadata: headers, timeout: .seconds(15)
    )
    let response = RPCResponse(message: Data([3, 4]), initialMetadata: headers, trailingMetadata: trailers)

    #expect(headers.entries == entries)
    #expect(request.method == "example.Service/Method")
    #expect(request.message == Data([1, 2]))
    #expect(request.metadata == headers)
    #expect(request.timeout == .seconds(15))
    #expect(response.message == Data([3, 4]))
    #expect(response.initialMetadata == headers)
    #expect(response.trailingMetadata == trailers)
    #expect(RPCRequest(method: "example.Service/Method", message: Data()).timeout == nil)
    #expect(RPCResponse(message: Data()).trailingMetadata.entries.isEmpty)
}

@Test
func `signature and status identifiers preserve future wire values`() {
    #expect(SignatureAlgorithm.mlDSA65.rawValue == "ML-DSA-65")
    #expect(SignatureAlgorithm(rawValue: "future-algorithm").description == "future-algorithm")
    #expect(RPCStatusCode(rawValue: 99).rawValue == 99)
    let codes: [RPCStatusCode] = [
        .ok, .cancelled, .unknown, .invalidArgument, .deadlineExceeded, .notFound,
        .alreadyExists, .permissionDenied, .resourceExhausted, .failedPrecondition,
        .aborted, .outOfRange, .unimplemented, .internalError, .unavailable, .dataLoss,
        .unauthenticated,
    ]
    #expect(codes.map(\.rawValue) == Array(0...16))
}

@Test
func `errors retain the original cause without formatting its secrets`() {
    let cause = CredentialBearingFailure()
    let trailers = RPCMetadata(entries: [
        .init(name: "details-bin", value: Data("credential-canary".utf8))
    ])
    let status = RPCStatusError(code: .unavailable, underlyingError: cause, trailingMetadata: trailers)
    let reservation = DeviceEnrollmentError.Reservation(
        id: DeviceID(UUID()), name: DeviceName(unchecked: "credential-canary")
    )
    let error = DeviceEnrollmentError(code: .deviceFailed, underlyingError: status, reservation: reservation)
    let retainedStatus = error.underlyingError as? RPCStatusError

    #expect(retainedStatus?.code == .unavailable)
    #expect(retainedStatus?.trailingMetadata == trailers)
    #expect(retainedStatus?.underlyingError as? CredentialBearingFailure === cause)
    #expect(error.reservation == reservation)
    for text in [
        error.message, error.description, String(reflecting: error),
        status.message, status.description, String(reflecting: status),
    ] {
        #expect(!text.contains("credential-canary"))
    }
}

@Test
func `all enrollment codes have distinct identifiers and safe messages`() {
    let codes: [DeviceEnrollmentError.Code] = [
        .notImplemented, .invalidName, .organizationMismatch, .alreadyEnrolled,
        .agentOutdated, .unsupported, .resetPending, .signerUnsupported, .permissionDenied,
        .nameUnavailable, .invalidRequest, .cloudUnsupported, .cloudUnavailable,
        .deviceIDCollisions, .invalidCredential, .deviceFailed, .identityMismatch, .outcomeUnknown,
    ]
    #expect(Set(codes).count == codes.count)
    for code in codes {
        let error = DeviceEnrollmentError(code: code, underlyingError: CredentialBearingFailure())
        #expect(error.code == code)
        #expect(!error.message.isEmpty)
        #expect(!error.description.contains("credential-canary"))
    }
}

private func configuration() throws -> DeviceEnrollment.Configuration {
    .init(
        cloudEndpoint: "api.example.test:443",
        certificateAuthority: try #require(URL(string: "https://acme.example.test")),
        requestAudience: "https://cloud.example.test/broker"
    )
}

private func isUnimplemented(_ error: any Error, operation: String) -> Bool {
    guard let error = error as? DeviceEnrollmentError else { return false }
    #expect(error.code == .notImplemented)
    #expect(error.reservation == nil)
    #expect(String(describing: error.underlyingError).contains(operation))
    #expect(!String(describing: error.underlyingError).contains("credential-canary"))
    return error.code == .notImplemented
}

private actor HostProbe: RPCTransport, OperatorSigner {
    nonisolated let algorithm = SignatureAlgorithm.mlDSA65
    private(set) var calls = 0

    func unary(_ request: RPCRequest) async throws -> RPCResponse {
        calls += 1
        throw UnexpectedHostCall()
    }

    func certificateChain() async throws -> [Data] {
        calls += 1
        throw UnexpectedHostCall()
    }

    func signature(for message: Data) async throws -> Data {
        calls += 1
        throw UnexpectedHostCall()
    }
}

private struct UnexpectedHostCall: Error {}

private final class CredentialBearingFailure: Error, CustomStringConvertible {
    let description = "Original transport failure with credential-canary."
}
