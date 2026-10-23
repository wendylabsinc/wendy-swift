# Enrolling a Device

Enroll a nearby WendyOS device in an organization using your app's signer and transports.

## Prepare the app capabilities

Use discovery in your app to select a device, then obtain the person's consent
before enrolling it. Supply these capabilities:

- An ``OperatorSigner`` bound to the selected organization's operator identity.
  On Apple platforms, implement it with the app's CryptoKit key. Keep that key
  bound to the returned certificate chain throughout the enrollment attempt.
- A Cloud ``RPCTransport`` that supplies your app's OAuth/DPoP authentication.
- A device ``RPCTransport`` connected to the selected, unprovisioned agent.
  Your app owns connection security and the lifetime of both transports.

Set ``DeviceEnrollment/Configuration`` to the Cloud endpoint, ACME service base
URL, and signed-request audience for the same environment. Use the organization's
tenant UUID, not its realm slug. Enrollment handles class B devices without
attestation.

## Check readiness and enroll

This function takes an already-confirmed device selection. It returns nil when
the agent is not ready; use ``EnrollmentReadiness/obstacle`` and
``EnrollmentReadiness/reason`` to explain that state in your app.

```swift
import Foundation
import WendySwift

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
```

Readiness is a snapshot, not a reservation. Enrollment checks the device again,
verifies the operator's organization, reads hardware best-effort, reserves the
Cloud identity, provisions the agent, and checks its returned principal.
``EnrolledDevice`` contains the permanent device ID, name, organization, and
certificate principal. It contains no one-time enrollment credential.

## Handle a failed attempt

Catch ``DeviceEnrollmentError`` and branch on its ``DeviceEnrollmentError/code``.
If ``DeviceEnrollmentError/reservation`` is present, Cloud has reserved the device
or may have done so before a response was lost. Confirm the Cloud state and
remove any reservation before starting a fresh attempt; do not automatically
retry the whole enrollment call.

Show the error's message together with redacted details from
``DeviceEnrollmentError/underlyingError``. The original cause retains transport
status and diagnostic context; it is not safe display or log text. Never log
RPC payloads or one-time enrollment credentials. Your transport must also keep
credential bytes out of the errors it supplies.
