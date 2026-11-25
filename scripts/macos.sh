#!/usr/bin/env bash
# The macOS SDK in macos/<version>/.
#
#   macos.sh pack               on a Mac: the current Xcode's SDK -> macos/<version>/sdk.tar.xz, version.plist
#   macos.sh create <version>   lay out macos/<version>/xcode from those two files
#
# Apple ships its SDK only with Xcode, so a Mac packs it once. Copy
# macos/<version>/ to any machine and run create there. The layout is a copy
# of Xcode holding only the SDK:
#
#   xcode/Contents/version.plist
#   xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX<version>.sdk
#   xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -> MacOSX<version>.sdk
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }
sdks_in_xcode=Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs

case "${1:-}" in
    pack)
        [[ "$(uname)" == Darwin ]] || die "pack runs on a Mac"
        sdk="$(xcrun --sdk macosx --show-sdk-path)"
        version="$(xcrun --sdk macosx --show-sdk-version)"
        out="$root/macos/$version"
        mkdir -p "$out"
        log "packing the macOS $version SDK"
        tar -C "$sdk/.." -cf - --exclude "$(basename "$sdk")/usr/share/man" "$(basename "$sdk")" \
            | xz -T0 > "$out/sdk.tar.xz"
        cp "$(xcode-select -p)/../version.plist" "$out/version.plist"
        log "packed $out; run create $version where it is laid out"
        ;;
    create)
        version="${2:-}"
        [[ -n "$version" ]] || die "usage: $(basename "$0") create <version>"
        dir="$root/macos/$version"
        [[ -f "$dir/sdk.tar.xz" && -f "$dir/version.plist" ]] \
            || die "no $dir/sdk.tar.xz and version.plist; make them on a Mac with: $(basename "$0") pack"
        # The archive holds MacOSX.sdk or MacOSX<version>.sdk.
        top="$(tar -tJf "$dir/sdk.tar.xz" --warning=no-unknown-keyword | sed -n 1p)"
        top="${top%%/*}"
        got="$(tar -xJOf "$dir/sdk.tar.xz" --warning=no-unknown-keyword "$top/SDKSettings.json" \
            | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["Version"])')"
        [[ "$got" == "$version" ]] || die "$dir/sdk.tar.xz holds the macOS $got SDK, not $version"
        xcode="$dir/xcode"
        if [[ -f "$xcode/$sdks_in_xcode/MacOSX$version.sdk/SDKSettings.json" ]] \
            && cmp -s "$dir/version.plist" "$xcode/Contents/version.plist"; then
            log "the macOS $version SDK is laid out already: $xcode"
        else
            # Laid out beside, then put in its place.
            new="$dir/xcode.new"
            rm -rf "$new"
            mkdir -p "$new/$sdks_in_xcode" "$new/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
            cp "$dir/version.plist" "$new/Contents/version.plist"
            log "unpacking the macOS $version SDK"
            tar -xJf "$dir/sdk.tar.xz" -C "$new/$sdks_in_xcode" --warning=no-unknown-keyword
            [[ "$top" == "MacOSX$version.sdk" ]] || mv "$new/$sdks_in_xcode/$top" "$new/$sdks_in_xcode/MacOSX$version.sdk"
            ln -s "MacOSX$version.sdk" "$new/$sdks_in_xcode/MacOSX.sdk"
            rm -rf "$xcode"
            mv "$new" "$xcode"
        fi
        "$root/scripts/check.sh" "macos/$version"
        ;;
    *) die "usage: $(basename "$0") pack | create <version>" ;;
esac
