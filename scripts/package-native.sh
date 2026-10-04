#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 3 ] || { echo 'Usage: package-native.sh vX.Y.Z <built-app> <new-output-directory>' >&2; exit 1; }
version="$1"
app="$2"
release_directory="$3"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a version such as v0.3.0' >&2; exit 1; }
[ -d "$app" ] && [ -f "$app/Contents/Info.plist" ] && [ -x "$app/Contents/MacOS/GlimpseMac" ] || {
    echo 'Expected a built GlimpseMac.app' >&2; exit 1;
}
[ "$(lipo -archs "$app/Contents/MacOS/GlimpseMac")" = arm64 ] || {
    echo 'The native preview must contain only arm64' >&2; exit 1;
}
[ ! -e "$release_directory" ] && [ ! -L "$release_directory" ] || {
    echo 'Release output already exists; use a new directory' >&2; exit 1;
}
mkdir "$release_directory"
package_directory="$(mktemp -d -t glimpse-native-package)"
trap 'rm -r "$package_directory"' EXIT
ditto --norsrc --noextattr "$app" "$package_directory/GlimpseMac.app"
cp docs/native-install.md "$package_directory/native-install.md"
strip -S "$package_directory/GlimpseMac.app/Contents/MacOS/GlimpseMac"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version#v}" "$package_directory/GlimpseMac.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version#v}" "$package_directory/GlimpseMac.app/Contents/Info.plist"
codesign --force --sign - --options runtime "$package_directory/GlimpseMac.app"
codesign --verify --deep --strict "$package_directory/GlimpseMac.app"
archive="GlimpseMac-$version-macos-arm64.zip"
ditto -c -k --norsrc --noextattr "$package_directory" "$release_directory/$archive"
cd "$release_directory"
shasum -a 256 "$archive" > SHA256SUMS
printf '%s\n' "Packaged $archive and SHA256SUMS"
