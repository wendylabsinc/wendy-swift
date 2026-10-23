import Foundation
import Testing
import WendySwift

// Mirrored from the guide and tour. Keep these examples in sync with their articles.

func enrollConfirmedDevice(
    configuration: DeviceEnrollment.Configuration,
    cloud: any RPCTransport,
    device: any RPCTransport,
    signer: any OperatorSigner,
    organizationUUID: UUID,
    requestedName: String
) async throws -> EnrolledDevice? {
    let organization = OrganizationID(organizationUUID)
    let name = try DeviceName(requestedName)
    let enrollment = DeviceEnrollment(
        configuration: configuration, cloud: cloud, signer: signer
    )
    let readiness = try await enrollment.readiness(of: device)
    guard readiness.isReady else { return nil }

    return try await enrollment.enroll(device, named: name, in: organization)
}

func makeEnrollmentClient(
    certificateAuthority: URL,
    cloud: any RPCTransport,
    signer: any OperatorSigner
) -> DeviceEnrollment {
    let configuration = DeviceEnrollment.Configuration(
        cloudEndpoint: "api.example.test:443",
        certificateAuthority: certificateAuthority,
        requestAudience: "https://cloud.example.test/broker"
    )
    return DeviceEnrollment(configuration: configuration, cloud: cloud, signer: signer)
}

func suggestedEnrollmentName(for host: String) throws -> DeviceName? {
    try DeviceName.suggested(forHost: host)
}

func reservationToCheck(after error: any Error) -> DeviceEnrollmentError.Reservation? {
    (error as? DeviceEnrollmentError)?.reservation
}

@Test
func `documentation examples type check without enrolling`() {
    // Refer to each example without invoking it or constructing host capabilities.
    _ = enrollConfirmedDevice
    _ = makeEnrollmentClient
    _ = suggestedEnrollmentName
    _ = reservationToCheck
}
