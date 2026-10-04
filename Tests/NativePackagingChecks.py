"""Package a synthetic executable, never launch an App or access Photos."""
import hashlib
import plistlib
from pathlib import Path
import subprocess
import tempfile
import zipfile


root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="glimpse-native-package-test-") as temporary:
    directory = Path(temporary)
    app = directory / "GlimpseMac.app"
    contents = app / "Contents"
    executable = contents / "MacOS" / "GlimpseMac"
    executable.parent.mkdir(parents=True)
    source = directory / "fixture.swift"
    source.write_text('print("Synthetic package fixture, not a Photos App")\n')
    subprocess.run(["swiftc", "-target", "arm64-apple-macos15.0", str(source), "-o", str(executable)],
                   check=True, timeout=60)
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "everthing.GlimpseMac", "CFBundleExecutable": "GlimpseMac",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "LSMinimumSystemVersion": "15.0", "NSPhotoLibraryUsageDescription": "Synthetic fixture only",
    }))
    output = directory / "release"
    command = ["bash", "scripts/package-native.sh", "v0.3.0", str(app), str(output)]
    subprocess.run(command, cwd=root, check=True, timeout=30)
    check_command = ["python3", "Tests/NativeReleaseChecks.py", str(output)]
    subprocess.run(check_command, cwd=root, check=True, timeout=30)
    checksum = (output / "SHA256SUMS").read_bytes()
    refused = subprocess.run(command, cwd=root, capture_output=True, timeout=30)
    assert refused.returncode != 0, "Existing release output must not be overwritten"
    assert (output / "SHA256SUMS").read_bytes() == checksum
    assert plistlib.loads((contents / "Info.plist").read_bytes())["CFBundleShortVersionString"] == "1.0", \
        "Packaging must not change the built input App"
    filename = checksum.decode().split()[1]
    archive = output / filename
    original_archive = archive.read_bytes()
    (output / "SHA256SUMS").write_text(f'{"0" * 64}  {filename}\n')
    rejected = subprocess.run(check_command, cwd=root, capture_output=True, timeout=30)
    assert rejected.returncode != 0 and b"Checksum mismatch" in rejected.stderr
    (output / "SHA256SUMS").write_bytes(checksum)
    with zipfile.ZipFile(archive, "a") as package:
        package.writestr("personal-photo.jpg", b"Synthetic fixture, not a real photo")
    (output / "SHA256SUMS").write_text(f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {filename}\n')
    rejected = subprocess.run(check_command, cwd=root, capture_output=True, timeout=30)
    assert rejected.returncode != 0 and b"Unexpected archive file" in rejected.stderr
    archive.write_bytes(original_archive)
    with zipfile.ZipFile(archive) as package:
        entries = [(member, package.read(member)) for member in package.infolist()]
    with zipfile.ZipFile(archive, "w") as package:
        for member, data in entries:
            if member.filename == "native-install.md":
                data += b"\n/Users/synthetic-release-fixture\n"
            package.writestr(member, data)
    (output / "SHA256SUMS").write_text(f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {filename}\n')
    rejected = subprocess.run(check_command, cwd=root, capture_output=True, timeout=30)
    assert rejected.returncode != 0 and b"local user paths" in rejected.stderr
    print("Native packaging checks passed: signature, no overwrite, input preserved; unsafe packages rejected")
