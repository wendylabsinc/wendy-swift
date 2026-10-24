"""Build the pinned WendyOS Core with its own packaging tools.

CI checks out WendyOS at scripts/core-revision. Local checkouts may be supplied
with --core-path. --test-host adds a test-only caller to the same Go archive;
production builds never contain that caller or a second Go runtime.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def build(core, test_host=False):
    revision = (ROOT / "scripts/core-revision").read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Core revision must be a full commit SHA")
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=core, text=True).strip()
    if actual != revision:
        raise ValueError(f"Core checkout {actual} differs from pin {revision}")
    driver = core / "cmd/wendy-core-native/swift_test_driver.go"
    if driver.exists():
        raise ValueError("Refusing to overwrite an existing test driver")
    try:
        if test_host:
            driver.write_bytes((ROOT / "Tests/BridgeSupport/driver.go.txt").read_bytes())
        subprocess.run(["python3", "scripts/build.py", "swift"], cwd=core, check=True)
    finally:
        if test_host:
            driver.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-path", type=Path, default=Path(os.environ.get("WENDY_CORE_PATH", ROOT / ".build/WendyOS/go/wendy-core")))
    parser.add_argument("--test-host", action="store_true")
    args = parser.parse_args()
    build(args.core_path.resolve(), args.test_host)
