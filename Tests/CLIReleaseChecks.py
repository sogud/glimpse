"""Verify the shipped CLI archive in an isolated runtime, without Photos access."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

directory = Path(sys.argv[1]).resolve()
digest, filename = (directory / "SHA256SUMS").read_text().split()
assert Path(filename).name == filename
archive_path = directory / filename
assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == digest
with tempfile.TemporaryDirectory(prefix="glimpse-release-check-") as temporary:
    installed = Path(temporary)
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        assert sorted(member.name for member in members) == ["cli-install.md", "glimpse"]
        assert all(member.isfile() for member in members), "archive must contain only regular files"
        for member in members:
            archive.extract(member, path=installed)
    binary = installed / "glimpse"
    assert binary.stat().st_mode & 0o111
    assert b"/Users/" not in binary.read_bytes(), "release binary must not embed local user paths"
    assert "arm64" in subprocess.check_output(["file", str(binary)], text=True)
    subprocess.run(["codesign", "--verify", "--strict", str(binary)], check=True)
    runtime = installed / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, GLIMPSE_HOME=str(runtime), GLIMPSE_TEST_BINARY=str(binary))
    subprocess.run([str(binary), "photos", "--help"], env=environment, check=True)
    subprocess.run([sys.executable, "Tests/CLICommandChecks.py"], env=environment, check=True,
                   cwd=Path(__file__).resolve().parents[1])
print("Release checks passed: checksum, archive allowlist, arm64, signature and installed CLI acceptance")
