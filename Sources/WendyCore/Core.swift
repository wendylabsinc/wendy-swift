internal import CWendyCore

/// Returns 42 from the statically linked Go engine.
public func WendyHelloWorld() -> Int32 { CWendyCore.WendyHelloWorld() }

/// The build identity stamped into the linked Core binary.
public func WendyCoreVersion() -> String { String(cString: CWendyCore.WendyCoreVersion()!) }
