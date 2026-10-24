"""Resolve assembled archives as an ordinary tagged SwiftPM dependency."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

from release import BEGIN, END, ROOT


def run(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True)


def smoke(assets, xcode_mcp=False):
    with tempfile.TemporaryDirectory(prefix="wendy-swift-consumer-") as temp:
        package = Path(temp) / "wendy-swift"
        package.mkdir()
        shutil.copytree(ROOT / "Sources", package / "Sources")
        shutil.copytree(ROOT / "Tests", package / "Tests")
        shutil.copytree(assets, package / "binaries")
        text = (ROOT / "Package.swift").read_text()
        targets = '''let binaryTargets: [Target] = [
    .binaryTarget(name: "CWendyCoreApple", path: "binaries/CWendyCore.xcframework.zip"),
    .binaryTarget(name: "CWendyCoreLinux", path: "binaries/CWendyCore.artifactbundle.zip"),
]
'''
        (package / "Package.swift").write_text(text[:text.index(BEGIN) + len(BEGIN)] + targets + text[text.index(END):])
        run("git", "init", "-q", "-b", "main", cwd=package)
        run("git", "add", ".", cwd=package)
        run("git", "-c", "user.name=SDK Test", "-c", "user.email=sdk@wendy.invalid", "commit", "-qm", "Test release manifest", cwd=package)
        run("git", "tag", "0.1.0-test.1", cwd=package)
        consumer = Path(temp) / "consumer"
        tests = consumer / "Tests/ConsumerTests"
        tests.mkdir(parents=True)
        (consumer / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "SDKConsumer", platforms: [.macOS(.v15), .iOS(.v18)],
    dependencies: [.package(url: "%s", exact: "0.1.0-test.1")],
    targets: [.testTarget(name: "ConsumerTests", dependencies: [.product(name: "WendySwift", package: "wendy-swift")])]
)
''' % package.as_uri())
        (tests / "Consumer.swift").write_text('''import Testing
import WendySwift
@Test func reachesStaticallyLinkedCore() {
    #expect(Wendy.helloWorld() == 42)
    #expect(!Wendy.coreVersion.isEmpty)
}
''')
        if xcode_mcp:
            run("xcodebuildmcp", "swift-package", "test", "--package-path", str(consumer), cwd=consumer)
        else:
            run("swift", "test", cwd=consumer)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", type=Path)
    parser.add_argument("--xcode-mcp", action="store_true")
    args = parser.parse_args()
    smoke(args.assets.resolve(), args.xcode_mcp)
