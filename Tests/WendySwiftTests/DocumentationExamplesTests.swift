import Foundation
import Testing
import WendySwift

// Mirrored from the guide and tour; compile these examples, but never invoke them.

func checkEnrollmentReadiness(
    enrollment: DeviceEnrollment,
    device: any RPCTransport
) async throws -> EnrollmentReadiness {
    try await enrollment.readiness(of: device)
}

func enrollConfirmedDevice(
    enrollment: DeviceEnrollment,
    device: any RPCTransport,
    organizationUUID: UUID,
    requestedName: String
) async throws -> EnrolledDevice {
    let organization = OrganizationID(organizationUUID)
    let name = try DeviceName(requestedName)
    return try await enrollment.enroll(device, named: name, in: organization)
}

@MainActor
private func tourEnrollmentCalls(
    configuration: DeviceEnrollment.Configuration,
    cloud: any RPCTransport,
    signer: any OperatorSigner,
    organizationUUID: UUID,
    deviceTransport: any RPCTransport,
    showReadiness: (EnrollmentReadiness.Obstacle, String?) -> Void,
    showEnrolledDevice: (EnrolledDevice) -> Void
) async throws {
    let enrollment = DeviceEnrollment(
        configuration: configuration, cloud: cloud, signer: signer
    )
    let name = try DeviceName("workbench")
    let organization = OrganizationID(organizationUUID)
    let readiness = try await enrollment.readiness(of: deviceTransport)
    if let obstacle = readiness.obstacle {
        showReadiness(obstacle, readiness.reason)
    }
    guard readiness.isReady else { return }
    let device = try await enrollment.enroll(
        deviceTransport, named: name, in: organization
    )
    showEnrolledDevice(device)
}

@MainActor
private func tourEnrollmentFailure(
    enrollment: DeviceEnrollment,
    deviceTransport: any RPCTransport,
    name: DeviceName,
    organization: OrganizationID,
    showEnrolledDevice: (EnrolledDevice) -> Void,
    showEnrollmentError: (DeviceEnrollmentError) -> Void,
    checkCloudReservation: (DeviceEnrollmentError.Reservation) -> Void
) async throws {
    do {
        let device = try await enrollment.enroll(
            deviceTransport, named: name, in: organization
        )
        showEnrolledDevice(device)
    } catch let error as DeviceEnrollmentError {
        showEnrollmentError(error)
        if let reservation = error.reservation {
            checkCloudReservation(reservation)
        }
    }
}

@Test
@MainActor
func `documentation examples type check without enrolling`() {
    // Refer to each example without invoking it or constructing host capabilities.
    _ = checkEnrollmentReadiness
    _ = enrollConfirmedDevice
    _ = tourEnrollmentCalls
    _ = tourEnrollmentFailure
}
