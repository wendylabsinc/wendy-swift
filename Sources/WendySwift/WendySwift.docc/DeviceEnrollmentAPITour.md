# Device Enrollment API Tour

Walk through the enrollment APIs in the order an app uses them.

## 1. Supply capabilities and configuration

``OperatorSigner`` exposes an algorithm, a leaf-first DER certificate chain, and
raw signatures over the exact JWS input. ``SignatureAlgorithm/mlDSA65`` identifies
the algorithm used for class B enrollment. The app keeps private-key custody.

``RPCTransport`` sends unary protobuf requests. Its ``RPCRequest`` carries the
method, serialized bytes, metadata, and timeout; ``RPCResponse`` separates initial
metadata from trailers. ``RPCMetadata`` preserves ordered, repeated entries and
binary values. An adapter reports a non-OK status using ``RPCStatusError`` and the
extensible ``RPCStatusCode``, retaining the original cause and trailers.

Build a ``DeviceEnrollment`` client from the Cloud transport, signer, and the
three environment settings. The device transport is supplied per operation.
These example hosts are placeholders for your deployment's endpoints.

```swift
import Foundation
import WendySwift

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
```

## 2. Choose an organization and name

``OrganizationID`` wraps the immutable tenant UUID. ``DeviceName`` validates an
organization-unique DNS label: 1–63 lowercase letters, digits, or hyphens, beginning
with a letter and not ending in a hyphen. Host-name suggestions lowercase the host
and remove `.local`; nil means no valid suggestion is available.

```swift
func suggestedEnrollmentName(for host: String) throws -> DeviceName? {
    try DeviceName.suggested(forHost: host)
}
```

Use ``DeviceName/init(_:)`` for the person's chosen label. The guide's
<doc:EnrollingADevice> example combines it with the organization and client.

## 3. Check the device and enroll it

Call ``DeviceEnrollment/readiness(of:)`` to obtain ``EnrollmentReadiness``.
An absent obstacle means the snapshot is ready. Otherwise, ``EnrollmentReadiness/Obstacle``
distinguishes an enrolled device, an outdated agent, an unsupported device, or a
pending reset. Discovery and consent stay in your app; there is no list API.

After consent, ``DeviceEnrollment/enroll(_:named:in:)`` returns ``EnrolledDevice``.
Its ``DeviceID`` is permanent and also identifies the Cloud asset. The result's
principal is the device's SPIFFE certificate identity; its name can change without
changing that identity. IDs and results are plain values, and all enrollment
values and capabilities are `Sendable`.

## 4. Preserve recovery information

``DeviceEnrollmentError/Code`` provides extensible failure categories. Compare
codes such as `.invalidName` or `.nameUnavailable` instead of parsing messages.
``DeviceEnrollmentError/Reservation`` identifies a known or possible Cloud
reservation without exposing the enrollment credential.

```swift
func reservationToCheck(after error: any Error) -> DeviceEnrollmentError.Reservation? {
    (error as? DeviceEnrollmentError)?.reservation
}
```

Use that reservation to guide a Cloud state check and removal before retrying.
The SDK message and debug text exclude original causes, metadata, and reservation
values. Keep the original error for diagnosis and redact its details before
presentation; a safe summary alone does not replace those details.
