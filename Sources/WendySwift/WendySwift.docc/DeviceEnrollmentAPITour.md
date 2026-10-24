# Device Enrollment API Tour

Use the new calls to prepare, enroll, and recover a device.

The examples use your app's configuration, signer, transports, organization UUID,
and UI callbacks. For transport and signing details, see <doc:WendySwift#App-capabilities>.

## 1. Make the client

Pass your Cloud transport and operator signer to ``DeviceEnrollment``.

```swift
let enrollment = DeviceEnrollment(
    configuration: configuration, cloud: cloud, signer: signer
)
```

## 2. Make a name

``DeviceName`` validates the chosen DNS label; ``OrganizationID`` takes the tenant UUID.

```swift
let name = try DeviceName("workbench")
let organization = OrganizationID(organizationUUID)
```

## 3. Check readiness

Check the selected device before offering enrollment, and present any obstacle and reason.

```swift
let readiness = try await enrollment.readiness(of: deviceTransport)
if let obstacle = readiness.obstacle {
    showReadiness(obstacle, readiness.reason)
}
```

## 4. Enroll

After a ready snapshot and the person's consent, enroll the device and use its returned identity.

```swift
let device = try await enrollment.enroll(
    deviceTransport, named: name, in: organization
)
showEnrolledDevice(device)
```

## 5. Handle a failure

Wrap the enrollment call to present its error with redacted cause details.
If it carries a reservation, confirm the Cloud state and remove any reservation before retrying.

```swift
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
```
