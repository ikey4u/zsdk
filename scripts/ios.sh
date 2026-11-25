#!/usr/bin/env bash
# Add the current Xcode's iPhone SDKs as ios/<version>/. Runs on a Mac.
#
#   ios.sh add
#
# The layout is a copy of Xcode holding only the iPhoneOS and iPhoneSimulator
# SDKs (without their manual pages), their platforms' Info.plists and the
# Swift libraries for iOS, and xcode/versions, the SDK's and Xcode's versions
# and builds.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }
plist_value() {
    python3 -I -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))[sys.argv[2]])' "$1" "$2"
}

[[ "${1:-}" == add ]] || die "usage: $(basename "$0") add"
[[ "$(uname)" == Darwin ]] || die "the iOS SDKs are added on a Mac, from its Xcode"
version="$(xcrun --sdk iphoneos --show-sdk-version)"
[[ "$(xcrun --sdk iphonesimulator --show-sdk-version)" == "$version" ]] \
    || die "the iPhoneOS and iPhoneSimulator SDKs' versions differ"
dir="$root/ios/$version"
[[ ! -e "$dir" ]] || die "$dir exists already"
xcode_developer="$(xcode-select -p)"

# Laid out beside, then put in its place.
new="$dir/xcode.new"
developer="$new/Contents/Developer"
mkdir -p "$developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift"
cp "$xcode_developer/../version.plist" "$new/Contents/version.plist"
for s in iPhoneOS iPhoneSimulator; do
    sdk="$(xcrun --sdk "$(echo "$s" | tr '[:upper:]' '[:lower:]')" --show-sdk-path)"
    sdks="$developer/Platforms/$s.platform/Developer/SDKs"
    mkdir -p "$sdks/$s$version.sdk"
    log "copying the $s $version SDK"
    tar -C "$sdk/" -cf - --exclude ./usr/share/man . | tar -C "$sdks/$s$version.sdk" -xf -
    # Under its versioned name, as in Xcode, and the plain one linking to it.
    ln -s "$s$version.sdk" "$sdks/$s.sdk"
    cp "$xcode_developer/Platforms/$s.platform/Info.plist" "$developer/Platforms/$s.platform/Info.plist"
done
log "copying the Swift libraries for iOS"
tar -C "$xcode_developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift" -cf - --exclude '*.swiftmodule' iphoneos iphonesimulator \
    | tar -C "$developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift" -xf -

sdk_build="$(plist_value "$developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$version.sdk/System/Library/CoreServices/SystemVersion.plist" ProductBuildVersion)"
xcode_verbatim="$(plist_value "$new/Contents/version.plist" CFBundleShortVersionString)"
xcode_build="$(plist_value "$new/Contents/version.plist" ProductBuildVersion)"
# 27.0 -> 2700, 16.4.1 -> 1641.
xcode_int="$(python3 -I -c 'import sys; p = (sys.argv[1].split(".") + ["0", "0"])[:3]; print(int(p[0]) * 100 + int(p[1]) * 10 + int(p[2]))' "$xcode_verbatim")"
cat > "$new/versions" << EOF
sdk_version $version
sdk_build $sdk_build
xcode_version_verbatim $xcode_verbatim
xcode_version_int $xcode_int
xcode_build $xcode_build
EOF
mv "$new" "$dir/xcode"
log "iOS SDK $version ($sdk_build), from Xcode $xcode_verbatim ($xcode_build): $dir/xcode"
"$root/scripts/check.sh" "ios/$version"
