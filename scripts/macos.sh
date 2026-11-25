#!/usr/bin/env bash
# Add the current Xcode's macOS SDK as macos/<version>/. Runs on a Mac.
#
#   macos.sh add
#
# The layout is a copy of Xcode holding only the SDK, without its manual pages:
#
#   xcode/Contents/version.plist
#   xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX<version>.sdk
#   xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -> MacOSX<version>.sdk
#   xcode/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }

[[ "${1:-}" == add ]] || die "usage: $(basename "$0") add"
[[ "$(uname)" == Darwin ]] || die "the macOS SDK is added on a Mac, from its Xcode"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
version="$(xcrun --sdk macosx --show-sdk-version)"
dir="$root/macos/$version"
[[ ! -e "$dir" ]] || die "$dir exists already"

# Laid out beside, then put in its place.
new="$dir/xcode.new"
sdks="$new/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"
mkdir -p "$sdks/MacOSX$version.sdk" "$new/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
# Git keeps no empty directory.
touch "$new/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/.keep"
cp "$(xcode-select -p)/../version.plist" "$new/Contents/version.plist"
log "copying the macOS $version SDK"
tar -C "$sdk/" -cf - --exclude ./usr/share/man . | tar -C "$sdks/MacOSX$version.sdk" -xf -
ln -s "MacOSX$version.sdk" "$sdks/MacOSX.sdk"
mv "$new" "$dir/xcode"
"$root/scripts/check.sh" "macos/$version"
