"""Assemble Core's platform archives and write the SwiftPM release manifest.

The workflow, not this script, creates the release-only commit and tag. Source
trigger tags use swift-preview/<version>; SwiftPM consumes the bare version.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BEGIN = "// BEGIN BINARY TARGETS\n"
END = "// END BINARY TARGETS\n"
VERSION = r"0\.1\.(?:0|[1-9][0-9]*)-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*"


def version(value):
    if not re.fullmatch(VERSION, value) or any(
        part.isdigit() and len(part) > 1 and part.startswith("0")
        for part in value.split("-", 1)[1].split(".")
    ):
        raise ValueError("Only SemVer 0.1.x pre-releases are supported")
    return value


def archive(directory, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as output:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                # Artifact download times must not change immutable checksums
                # when the publication job alone is retried.
                info = zipfile.ZipInfo(path.relative_to(directory.parent).as_posix())
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                output.writestr(info, path.read_bytes())


def collect(downloads, output, prefix):
    for target in ("macos", "linux-x64", "linux-arm64"):
        source = downloads / (prefix + target)
        destination = output / target
        if target != "macos":
            destination /= "CWendyCore.artifactbundle"
        shutil.copytree(source, destination)


def assemble(inputs, output):
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(inputs / "macos/CWendyCore.xcframework.zip", output / "CWendyCore.xcframework.zip")
    # Each input was produced by Core's own artifact_bundle helper. Merge the
    # Linux variants without rebuilding the already tested static libraries.
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        merged = root / "CWendyCore.artifactbundle"
        variants = []
        for target in ("linux-x64", "linux-arm64"):
            source = inputs / target / "CWendyCore.artifactbundle"
            info = json.loads((source / "info.json").read_text())
            entries = info["artifacts"]["CWendyCore"]["variants"]
            if len(entries) != 1:
                raise ValueError("Expected one Linux variant per native build")
            if not merged.exists():
                shutil.copytree(source, merged)
                identity = info
            else:
                if info["artifacts"]["CWendyCore"]["version"] != identity["artifacts"]["CWendyCore"]["version"]:
                    raise ValueError("Core build identities differ")
                for name in ("include",):
                    for path in (source / name).rglob("*"):
                        if path.is_file() and path.read_bytes() != (merged / path.relative_to(source)).read_bytes():
                            raise ValueError("Core headers differ between Linux variants")
                variant_directory = Path(entries[0]["path"]).parent
                shutil.copytree(source / variant_directory, merged / variant_directory)
            variants.extend(entries)
        identity["artifacts"]["CWendyCore"]["variants"] = variants
        (merged / "info.json").write_text(json.dumps(identity, indent=2) + "\n")
        archive(merged, output / "CWendyCore.artifactbundle.zip")


def manifest(text, value, directory):
    version(value)
    if text.count(BEGIN) != 1 or text.count(END) != 1 or text.index(BEGIN) > text.index(END):
        raise ValueError("Expected one binary target block")
    targets = []
    for name, file in (("CWendyCoreApple", "CWendyCore.xcframework.zip"), ("CWendyCoreLinux", "CWendyCore.artifactbundle.zip")):
        checksum = hashlib.sha256((directory / file).read_bytes()).hexdigest()
        url = f"https://github.com/wendylabsinc/wendy-swift/releases/download/{value}/{file}"
        targets.append(f'    .binaryTarget(name: "{name}", url: "{url}", checksum: "{checksum}"),')
    replacement = "let binaryTargets: [Target] = [\n" + "\n".join(targets) + "\n]\n"
    return text[:text.index(BEGIN) + len(BEGIN)] + replacement + text[text.index(END):]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["collect", "assemble", "manifest", "version"])
    parser.add_argument("--version")
    parser.add_argument("--downloads", type=Path, default=ROOT / ".build/downloads")
    parser.add_argument("--prefix", default="release-core-")
    parser.add_argument("--inputs", type=Path, default=ROOT / ".build/release-inputs")
    parser.add_argument("--assets", type=Path, default=ROOT / ".build/release-assets")
    args = parser.parse_args()
    if args.command == "version":
        print(version(args.version))
    elif args.command == "collect":
        collect(args.downloads, args.inputs, args.prefix)
    elif args.command == "assemble":
        assemble(args.inputs, args.assets)
    else:
        path = ROOT / "Package.swift"
        path.write_text(manifest(path.read_text(), args.version, args.assets))
