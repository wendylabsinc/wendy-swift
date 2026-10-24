#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Signs enrollment requests using an operator key held by the app.
///
/// The app supplies the signing implementation, such as CryptoKit on Apple
/// platforms. The private key never crosses this interface.
public protocol OperatorSigner: Sendable {
    /// The signature algorithm of the held key; class B enrollment requires ML-DSA-65.
    var algorithm: SignatureAlgorithm { get }

    /// Returns the operator's DER certificate chain, leaf first, renewing it if needed.
    ///
    /// The chain must remain bound to the key used for the following signatures.
    func certificateChain() async throws -> [Data]

    /// Signs the exact message bytes without pre-hashing by the SDK.
    ///
    /// Receives a complete JWS signing input and returns the raw signature bytes.
    /// Implementations must cooperate with task cancellation and keep secrets out of errors.
    func signature(for message: Data) async throws -> Data
}

/// An extensible JOSE signature algorithm identifier.
public struct SignatureAlgorithm: Hashable, Sendable, RawRepresentable, CustomStringConvertible {
    /// The ML-DSA-65 algorithm used for class B enrollment.
    public static let mlDSA65 = Self(rawValue: "ML-DSA-65")

    /// The JOSE algorithm name.
    public let rawValue: String

    /// The algorithm name as text.
    public var description: String { rawValue }

    /// Creates an identifier without asserting that enrollment supports the algorithm.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
