"""Generate the binding envelope and unchanged Cloud Asset projection.

Requires protoc and protoc-gen-swift from swift-protobuf 1.39.0. The pinned
WendyOS checkout supplies both authoritative schemas. Only Asset/AssetKind are
projected from the Cloud service file; no unrelated RPC API is added to Swift.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, kind, name):
    match = re.search(rf"^{kind} {name} \{{.*?^\}}", source, re.M | re.S)
    if not match:
        raise ValueError(f"Missing {name}")
    return match.group()


def generate(core, plugin):
    pin = (ROOT / "scripts/core-revision").read_text().strip()
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=core, text=True).strip()
    if actual != pin:
        raise ValueError("Schema checkout differs from Core pin")
    source = (core.parents[1] / "Proto/wendycloud/v2/assets.proto").read_text()
    asset = '\n'.join([
        '// Projected unchanged from WendyOS ' + pin + ' Proto/wendycloud/v2/assets.proto.',
        'syntax = "proto3";', 'package wendycloud.v2;',
        'import "google/protobuf/struct.proto";', 'import "google/protobuf/timestamp.proto";',
        declaration(source, 'enum', 'AssetKind'), declaration(source, 'message', 'Asset'), '',
    ])
    output = ROOT / 'Sources/WendySwift/Generated'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        staging = Path(directory)
        for name, schema, visibility in [
            ('core', (core / 'proto/wendy/core/v1/core.proto').read_text(), 'Internal'),
            ('assets', asset, 'Public'),
        ]:
            (staging / (name + '.proto')).write_text(schema)
            subprocess.run(['protoc', '-I' + directory, '--plugin=protoc-gen-swift=' + str(plugin),
                            '--swift_out=' + str(output), '--swift_opt=Visibility=' + visibility + ',UseAccessLevelOnImports=true',
                            str(staging / (name + '.proto'))], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-path', type=Path, default=ROOT / '.build/WendyOS/go/wendy-core')
    parser.add_argument('--plugin', type=Path, required=True)
    args = parser.parse_args()
    generate(args.core_path.resolve(), args.plugin.resolve())
