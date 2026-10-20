internal import WendyCore

/// The Wendy SDK for Swift, built on Wendy Core.
///
/// Shared behavior lives in Wendy Core, so a fix there reaches every client
/// and language. This SDK adds Swift conveniences, not its own product behavior.
public enum Wendy {
    /// Returns 42 from Wendy Core: a temporary operation that proves the SDK
    /// reaches the shared engine.
    public static func helloWorld() -> Int32 {
        WendyHelloWorld()
    }
}
