# zsdk

The macOS, iOS and Windows SDKs, laid out to cross-compile from Linux. There's one directory per platform and one subdirectory per SDK version.

| Directory | SDK |
|---|---|
| `macos/27.0/` | macOS 27.0 SDK (Xcode 27.0, 27A266a), with arm64 and x86_64 libraries |
| `ios/27.0/` | iPhoneOS and iPhoneSimulator 27.0 SDKs (Xcode 27.0) |
| `windows/10.0.28000/` | Windows SDK 10.0.28000.0, MSVC 14.50.35717, DIA SDK |

## Tasks

| Command | Does |
|---|---|
| `mise run check [platform/version]` | Checks that each SDK is complete, offline |
| `mise run create:windows` | Downloads the pinned MSVC and Windows SDK packages and lays them out in `windows/<version>/` |
| `mise run pack:macos` | On a Mac: packs the current Xcode's macOS SDK into `macos/<version>/` |
| `mise run create:macos <version>` | Lays out `macos/<version>/xcode` from its `sdk.tar.xz` |
| `mise run pack:ios` | On a Mac: packs the current Xcode's iPhone SDKs into `ios/<version>/in/` |
| `mise run create:ios <version>` | Lays out `ios/<version>/xcode` from `in/` |

`scripts/windows.py` pins each Windows package by version and SHA-256. `scripts/windows.py json windows/<version>` prints the toolchain's `win_toolchain.json`, and `scripts/windows.py case-links windows/<version> <src>...` links the header and library names a source tree uses in another case.

## Licence

The Apple SDKs belong to Apple. The Visual Studio and Windows SDK files belong to Microsoft. Each is subject to its owner's licence terms. They're provided for development and testing only, not for commercial use.
