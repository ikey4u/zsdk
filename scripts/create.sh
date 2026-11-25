#!/usr/bin/env bash
# Lay out an SDK in <platform>/<version>/ of this repository.
#
#   create.sh windows [version]   default: the Windows SDK zebkit pins
#   create.sh macos <version>     on Linux, from macos/<version>/sdk.tar.xz and version.plist
#   create.sh macos               on a Mac: pack the current Xcode's SDK into macos/<version>/
#
#   ZEBKIT_ROOT   a zebkit checkout; its scripts pin and lay out the SDKs (Linux only)
#
# windows: everything is downloaded, by SHA-256. Running this accepts
#   Microsoft's licence terms for Visual Studio and the Windows SDK.
# macos: Apple ships its SDK only with Xcode, so a Mac has to pack it once.
#   Copy macos/<version>/ to the Linux machine, then run this there.
#
# What exists is reused. A piece is fetched again only when the pins change.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
platform="${1:-}"
version="${2:-}"
die() { echo "error: $*" >&2; exit 1; }
case "$platform" in windows|macos) ;; *) die "usage: $(basename "$0") windows|macos [version]" ;; esac

if [[ "$(uname)" == Darwin ]]; then
    [[ "$platform" == macos ]] || die "the Windows SDK is laid out on Linux"
    sdk="$(xcrun --show-sdk-path)"
    version="${version:-$(xcrun --show-sdk-version)}"
    out="$root/macos/$version"
    mkdir -p "$out"
    tar -C "$sdk/.." -cf - --exclude 'MacOSX.sdk/usr/share/man' "$(basename "$sdk")" \
        | xz -T0 > "$out/sdk.tar.xz"
    cp "$(xcode-select -p)/../version.plist" "$out/version.plist"
    echo "packed $out: copy it to macos/$version/ on the Linux machine and run this there"
    exit 0
fi

[[ -n "${ZEBKIT_ROOT:-}" && -f "$ZEBKIT_ROOT/scripts/lib.sh" ]] \
    || die "set ZEBKIT_ROOT to a zebkit checkout"

if [[ "$platform" == windows && -z "$version" ]]; then
    # The pinned SDK, e.g. 10.0.28000.0, without its last field.
    version="$(sed -n 's/^SDK_VERSION = "\(.*\)\.[0-9]*"$/\1/p' "$ZEBKIT_ROOT/scripts/windows-toolchain.py")"
    [[ -n "$version" ]] || die "no SDK_VERSION in $ZEBKIT_ROOT/scripts/windows-toolchain.py"
fi
[[ -n "$version" ]] || die "usage: $(basename "$0") macos <version>"
out="$root/$platform/$version"

# zebkit's scripts lay out $ZEBKIT_SDK_DIR/<platform>. They are given a
# directory in which <platform> is this version's directory.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$out"
ln -s "$out" "$stage/$platform"
export ZEBKIT_SDK_DIR="$stage" ZEBKIT_SDK_NO_LINK=1

if [[ "$platform" == windows ]]; then
    "$ZEBKIT_ROOT/scripts/windows-toolchain.sh" --no-link
else
    [[ -f "$out/sdk.tar.xz" && -f "$out/version.plist" ]] \
        || die "no $out/sdk.tar.xz and version.plist: run this script on a Mac and copy them here"
    "$ZEBKIT_ROOT/scripts/macos-toolchain.sh" "$out/sdk.tar.xz" "$out/version.plist"
fi

"$root/scripts/check.sh" "$platform/$version"
