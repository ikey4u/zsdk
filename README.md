# zsdk

The macOS, iOS and Windows SDKs, laid out to cross-compile from Linux. There's one directory per platform and one subdirectory per SDK version.

| Directory | SDK |
|---|---|
| `macos/27.0/` | macOS 27.0 SDK (Xcode 27.0, 27A266a), with arm64 and x86_64 libraries |
| `ios/27.0/` | iPhoneOS and iPhoneSimulator 27.0 SDKs (Xcode 27.0) |
| `windows/10.0.28000/` | Windows SDK 10.0.28000.0, MSVC 14.50.35717, DIA SDK |

## Use

Clone the repository. The SDKs are already laid out, so there's nothing to run. To fetch only the versions you need:

```sh
git clone --filter=blob:none --sparse https://github.com/ikey4u/zsdk.git
cd zsdk && git sparse-checkout add macos/27.0 windows/10.0.28000
```

`mise run check [platform/version]` checks that an SDK is complete, offline. `scripts/windows.py json windows/<version>` prints the toolchain's `win_toolchain.json`. `scripts/windows.py case-links windows/<version> <src>...` links the header and library names a source tree uses in another case.

## Add a version

Only needed to add a new SDK version to this repository:

| Command | Does |
|---|---|
| `mise run add:macos` | On a Mac: adds the current Xcode's macOS SDK as `macos/<version>/` |
| `mise run add:ios` | On a Mac: adds the current Xcode's iPhone SDKs as `ios/<version>/` |
| `mise run add:windows <version>` | Downloads the MSVC, Windows SDK and debugger packages that `windows/<version>/pins.json` pins, by version and SHA-256, and lays them out there |

[docs/windows.md](docs/windows.md) lists where each Windows version's packages and the Windows SDK ISO come from, with their checksums, so they can be downloaded and checked by hand.

For a new Windows version, write `windows/<version>/pins.json` first, starting from an existing one. `<version>` is the SDK's version without its last field, such as `10.0.28000` for `10.0.28000.0`.

## Licence

The Apple SDKs belong to Apple. The Visual Studio and Windows SDK files belong to Microsoft. Each is subject to its owner's licence terms. They're provided for development and testing only, not for commercial use.
