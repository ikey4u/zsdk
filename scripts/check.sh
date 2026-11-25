#!/usr/bin/env bash
# Check that each laid-out SDK is complete. Reads the disk only.
#
#   check.sh [<platform>/<version> ...]   default: every one in this repository
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"
failed=0
fail() { echo "  FAIL $*"; failed=1; }
ok() { echo "  ok   $*"; }

check_macos() {
    local sdk="$1/xcode/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    [[ -f "$sdk/SDKSettings.json" ]] && ok "MacOSX.sdk" || { fail "no $sdk"; return; }
    local version
    version="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["Version"])' "$sdk/SDKSettings.json")"
    [[ "$version" == "${1#*/}" ]] && ok "version $version" || fail "MacOSX.sdk is $version"
    for arch in arm64 x86_64; do
        grep -q "$arch-macos" "$sdk/usr/lib/libSystem.B.tbd" && ok "libSystem has $arch" || fail "libSystem has no $arch"
    done
}

check_ios() {
    local platforms="$1/xcode/Contents/Developer/Platforms"
    for name in iPhoneOS iPhoneSimulator; do
        [[ -f "$platforms/$name.platform/Developer/SDKs/$name.sdk/SDKSettings.json" ]] \
            && ok "$name.sdk" || fail "no $name.sdk"
    done
    grep -qx "sdk_version ${1#*/}" "$1/xcode/versions" 2> /dev/null \
        && ok "versions" || fail "no xcode/versions for ${1#*/}"
}

check_windows() {
    if python3 -I "$root/scripts/windows.py" verify "$1"; then
        ok "the pinned MSVC and Windows SDK"
    else
        fail "not the pinned toolchain"
    fi
    local sdk="${1#*/}"
    [[ -d "$1/vs_files/Windows Kits/10/Include/$sdk.0" ]] && ok "Windows SDK $sdk" || fail "no Windows SDK $sdk"
}

targets=("$@")
if (( ${#targets[@]} == 0 )); then
    for dir in macos/*/ ios/*/ windows/*/; do [[ -d "$dir" ]] && targets+=("${dir%/}"); done
fi
for target in "${targets[@]}"; do
    echo "$target"
    [[ -d "$target" ]] || { fail "no such directory"; continue; }
    case "${target%%/*}" in
        macos) check_macos "$target" ;;
        ios) check_ios "$target" ;;
        windows) check_windows "$target" ;;
        *) fail "unknown platform" ;;
    esac
done
exit "$failed"
