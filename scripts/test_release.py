import hashlib
import json
import os
import zipfile
import tempfile
from pathlib import Path
import unittest

import release


class ReleaseTests(unittest.TestCase):
    def test_assembles_linux_variants_and_retries_with_identical_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            inputs, assets = root / "inputs", root / "assets"
            (inputs / "macos").mkdir(parents=True)
            (inputs / "macos/CWendyCore.xcframework.zip").write_bytes(b"tested apple archive")
            for target, triple in (("linux-x64", "x86_64-unknown-linux-gnu"), ("linux-arm64", "aarch64-unknown-linux-gnu")):
                bundle = inputs / target / "CWendyCore.artifactbundle"
                (bundle / triple).mkdir(parents=True)
                (bundle / triple / "libCWendyCore.a").write_bytes(target.encode())
                (bundle / "include").mkdir()
                (bundle / "include/WendyPlatform.h").write_bytes(b"same header")
                (bundle / "info.json").write_text(json.dumps({"schemaVersion": "1.0", "artifacts": {"CWendyCore": {
                    "type": "staticLibrary", "version": "0.1.0-dev+abcdef0", "variants": [{
                        "path": triple + "/libCWendyCore.a", "supportedTriples": [triple],
                    }],
                }}}))
            release.assemble(inputs, assets)
            path = assets / "CWendyCore.artifactbundle.zip"
            first = path.read_bytes()
            with zipfile.ZipFile(path) as archive:
                info = json.loads(archive.read("CWendyCore.artifactbundle/info.json"))
                self.assertEqual(len(info["artifacts"]["CWendyCore"]["variants"]), 2)
            for file in inputs.rglob("*"):
                os.utime(file, (1234567890, 1234567890))
            release.assemble(inputs, assets)
            self.assertEqual(first, path.read_bytes())
            (inputs / "linux-arm64/CWendyCore.artifactbundle/include/WendyPlatform.h").write_bytes(b"different header")
            with self.assertRaisesRegex(ValueError, "headers differ"):
                release.assemble(inputs, assets)

    def test_manifest_pins_both_assets_and_preserves_package(self):
        text = (release.ROOT / "Package.swift").read_text()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            for file in ("CWendyCore.xcframework.zip", "CWendyCore.artifactbundle.zip"):
                (directory / file).write_bytes(file.encode())
            output = release.manifest(text, "0.1.0-seed.2", directory)
            self.assertIn('releases/download/0.1.0-seed.2/CWendyCore.xcframework.zip', output)
            self.assertIn(hashlib.sha256(b"CWendyCore.artifactbundle.zip").hexdigest(), output)
            self.assertNotIn('Context.environment["WENDY_CORE_PATH"]', output)
            self.assertEqual(text.split(release.END)[1], output.split(release.END)[1])

    def test_rejects_stable_invalid_or_injected_versions(self):
        for value in ("0.1.0", "1.0.0-seed.1", "0.1.0-seed.01", '0.1.0-x\"', "0.1.0-x/y", "0.1.0-x\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.version(value)

    def test_rejects_ambiguous_manifest_blocks(self):
        with self.assertRaises(ValueError):
            release.manifest("no markers", "0.1.0-seed.2", Path("."))


if __name__ == "__main__":
    unittest.main()
