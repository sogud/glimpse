#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
version="${1:-}"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a version such as v0.2.0' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo 'Build this CLI release on Apple Silicon' >&2; exit 1; }
swift build -c release --product glimpse
binary_directory="$(swift build -c release --show-bin-path)"
release_directory=".build/releases/$version"
[ ! -e "$release_directory" ] || { echo 'Release output already exists; use a new version or inspect it first' >&2; exit 1; }
mkdir -p "$release_directory"
package_directory="$(mktemp -d)"
trap 'rm -r "$package_directory"' EXIT
cp "$binary_directory/glimpse" "$package_directory/glimpse"
cp docs/cli-install.md "$package_directory/cli-install.md"
strip -S "$package_directory/glimpse"
codesign --force --sign - "$package_directory/glimpse"
codesign --verify --strict "$package_directory/glimpse"
archive="glimpse-$version-macos-arm64.tar.gz"
COPYFILE_DISABLE=1 tar -czf "$release_directory/$archive" -C "$package_directory" glimpse cli-install.md
cd "$release_directory"
shasum -a 256 "$archive" > SHA256SUMS
printf '%s\n' "Packaged $archive and SHA256SUMS"
