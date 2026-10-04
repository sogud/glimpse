"""Check a native archive without launching the App or accessing Photos."""
import hashlib
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile


directory = Path(sys.argv[1]).resolve()
digest, filename = (directory / "SHA256SUMS").read_text().split()
match = re.fullmatch(r"GlimpseMac-v([0-9]+\.[0-9]+\.[0-9]+)-macos-arm64\.zip", filename)
assert match, "Unexpected archive name"
archive_path = directory / filename
assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == digest, "Checksum mismatch"
allowed_files = {
    "native-install.md", "GlimpseMac.app/Contents/Info.plist", "GlimpseMac.app/Contents/PkgInfo",
    "GlimpseMac.app/Contents/MacOS/GlimpseMac", "GlimpseMac.app/Contents/_CodeSignature/CodeResources",
}
required_files = allowed_files - {"GlimpseMac.app/Contents/PkgInfo"}
allowed_directories = {
    "GlimpseMac.app/", "GlimpseMac.app/Contents/", "GlimpseMac.app/Contents/MacOS/",
    "GlimpseMac.app/Contents/_CodeSignature/", "GlimpseMac.app/Contents/Resources/",
}
with tempfile.TemporaryDirectory(prefix="glimpse-native-release-check-") as temporary:
    installed = Path(temporary)
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), "Duplicate archive entries"
        assert required_files.issubset(names), "Incomplete App package"
        for member in archive.infolist():
            mode = member.external_attr >> 16
            if member.is_dir():
                assert member.filename in allowed_directories, "Unexpected archive directory"
                continue
            assert member.filename in allowed_files, "Unexpected archive file"
            assert stat.S_ISREG(mode), "Only regular files are allowed"
            contents = archive.read(member)
            assert b"/Users/" not in contents, "Package must not embed local user paths"
            target = installed / member.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
            target.chmod(stat.S_IMODE(mode))
    app = installed / "GlimpseMac.app"
    executable = app / "Contents/MacOS/GlimpseMac"
    assert executable.stat().st_mode & 0o111, "Executable permission missing"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "everthing.GlimpseMac"
    assert info["CFBundleExecutable"] == "GlimpseMac"
    assert info["CFBundlePackageType"] == "APPL"
    assert info["CFBundleShortVersionString"] == match[1]
    assert info["CFBundleVersion"] == match[1]
    assert info["LSMinimumSystemVersion"] == "15.0"
    assert info["NSPhotoLibraryUsageDescription"]
    assert subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip() == "arm64"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print("Native archive checks passed: checksum, contents, arm64 and signature; App not launched")
