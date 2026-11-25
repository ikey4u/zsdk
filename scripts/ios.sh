#!/usr/bin/env bash
# The iOS SDKs in ios/<version>/.
#
#   ios.sh pack               on a Mac: the current Xcode's iPhone SDKs -> ios/<version>/in/
#   ios.sh create <version>   lay out ios/<version>/xcode from ios/<version>/in/
#
# in/ holds iPhoneOS.sdk.tar.xz, iPhoneSimulator.sdk.tar.xz, their platforms'
# Info.plists, the Swift libraries for iOS (swift-ios-libs.tar.xz) and
# Xcode's version.plist, about 40 MB. The layout is a copy of Xcode holding
# only those, and xcode/versions, the SDK's and Xcode's versions and builds.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }
inputs=(iPhoneOS.sdk.tar.xz iPhoneSimulator.sdk.tar.xz iPhoneOS.platform.Info.plist
        iPhoneSimulator.platform.Info.plist swift-ios-libs.tar.xz version.plist)
plist_value() {
    python3 -I -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))[sys.argv[2]])' "$1" "$2"
}

case "${1:-}" in
    pack)
        [[ "$(uname)" == Darwin ]] || die "pack runs on a Mac"
        version="$(xcrun --sdk iphoneos --show-sdk-version)"
        out="$root/ios/$version/in"
        mkdir -p "$out"
        platforms="$(xcode-select -p)/Platforms"
        for s in iPhoneOS iPhoneSimulator; do
            log "packing the $s $version SDK"
            (cd "$platforms/$s.platform/Developer/SDKs" \
                && tar -cf - --exclude "$s.sdk/usr/share/man" "$s.sdk") | xz -T0 > "$out/$s.sdk.tar.xz"
            cp "$platforms/$s.platform/Info.plist" "$out/$s.platform.Info.plist"
        done
        (cd "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib" \
            && tar -cf - --exclude '*.swiftmodule' swift/iphoneos swift/iphonesimulator) | xz -T0 > "$out/swift-ios-libs.tar.xz"
        cp "$(xcode-select -p)/../version.plist" "$out/version.plist"
        log "packed $out; run create $version where it is laid out"
        ;;
    create)
        version="${2:-}"
        [[ -n "$version" ]] || die "usage: $(basename "$0") create <version>"
        dir="$root/ios/$version"
        for f in "${inputs[@]}"; do
            [[ -f "$dir/in/$f" ]] || die "no $dir/in/$f; make in/ on a Mac with: $(basename "$0") pack"
        done
        # Laid out beside, then put in its place.
        new="$dir/xcode.new"
        developer="$new/Contents/Developer"
        rm -rf "$new"
        mkdir -p "$developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
        cp "$dir/in/version.plist" "$new/Contents/version.plist"
        for s in iPhoneOS iPhoneSimulator; do
            sdks="$developer/Platforms/$s.platform/Developer/SDKs"
            mkdir -p "$sdks"
            log "unpacking the $s SDK"
            tar -xJf "$dir/in/$s.sdk.tar.xz" -C "$sdks" --warning=no-unknown-keyword
            got="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["Version"])' "$sdks/$s.sdk/SDKSettings.json")"
            [[ "$got" == "$version" ]] || die "$s.sdk.tar.xz holds the $got SDK, not $version"
            # Under its versioned name, as in Xcode, and the plain one linking to it.
            mv "$sdks/$s.sdk" "$sdks/$s$version.sdk"
            ln -s "$s$version.sdk" "$sdks/$s.sdk"
            cp "$dir/in/$s.platform.Info.plist" "$developer/Platforms/$s.platform/Info.plist"
        done
        tar -xJf "$dir/in/swift-ios-libs.tar.xz" -C "$developer/Toolchains/XcodeDefault.xctoolchain/usr/lib" \
            --warning=no-unknown-keyword
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
        rm -rf "$dir/xcode"
        mv "$new" "$dir/xcode"
        log "iOS SDK $version ($sdk_build), from Xcode $xcode_verbatim ($xcode_build): $dir/xcode"
        "$root/scripts/check.sh" "ios/$version"
        ;;
    *) die "usage: $(basename "$0") pack | create <version>" ;;
esac
