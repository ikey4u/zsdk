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
    local tbd="$sdk/usr/lib/libSystem.B.tbd"
    for arch in arm64 x86_64; do
        grep -q "$arch-macos" "$tbd" && ok "libSystem has $arch" || fail "libSystem has no $arch"
    done
    ls "$1"/runtime/lib/clang/*/lib/darwin/libclang_rt.osx.a > /dev/null 2>&1 \
        && ok "compiler runtime" || fail "no libclang_rt.osx.a in $1/runtime"
}

check_ios() {
    local platforms="$1/xcode/Contents/Developer/Platforms"
    for name in iPhoneOS iPhoneSimulator; do
        [[ -f "$platforms/$name.platform/Developer/SDKs/$name.sdk/SDKSettings.json" ]] \
            && ok "$name.sdk" || fail "no $name.sdk"
    done
}

check_windows() {
    local json="$1/win_toolchain.json"
    [[ -f "$json" ]] || { fail "no $json"; return; }
    python3 -I - "$json" << 'EOF' || failed=1
import json, os, sys
d = json.load(open(sys.argv[1]))
for path in [d["path"], d["win_sdk"], d["wdk"], *d["runtime_dirs"]]:
    print(f"  {'ok  ' if os.path.isdir(path) else 'FAIL'} {path}")
    if not os.path.isdir(path):
        sys.exit(1)
EOF
    [[ -x "$1/rc" ]] && ok "rc" || fail "no $1/rc"
}

targets=("$@")
if (( ${#targets[@]} == 0 )); then
    for dir in macos/*/ ios/*/ windows/*/; do [[ -d "$dir" ]] && targets+=("${dir%/}"); done
fi
for target in "${targets[@]}"; do
    platform="${target%%/*}"
    [[ -d "$target" ]] || { echo "$target"; fail "no such directory"; continue; }
    echo "$target"
    case "$platform" in
        macos) check_macos "$target" ;;
        ios) check_ios "$target" ;;
        windows) check_windows "$target" ;;
        *) fail "unknown platform $platform" ;;
    esac
done
exit "$failed"
