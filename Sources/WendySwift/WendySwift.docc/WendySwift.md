# ``WendySwift``

Connect Wendy apps to shared device capabilities through a Swift API.

## Overview

WendySwift builds on Wendy Core. Apps provide platform capabilities such as
operator signing and RPC transport; shared product behavior belongs in Core.
The package supports macOS 15+, iOS 18+, and Linux with Swift 6.2 or later.

Start with <doc:EnrollingADevice> for the enrollment task, or read
<doc:DeviceEnrollmentAPITour> for a tour of the types and their responsibilities.

## Topics

### Device enrollment

- <doc:EnrollingADevice>
- <doc:DeviceEnrollmentAPITour>
- ``DeviceEnrollment``
- ``DeviceName``
- ``OrganizationID``
- ``DeviceID``
- ``EnrollmentReadiness``
- ``EnrolledDevice``
- ``DeviceEnrollmentError``

### App capabilities

- ``OperatorSigner``
- ``SignatureAlgorithm``
- ``RPCTransport``
- ``RPCRequest``
- ``RPCResponse``
- ``RPCMetadata``
- ``RPCStatusError``
- ``RPCStatusCode``

### Core information

- ``Wendy``
