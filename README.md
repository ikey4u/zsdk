# zsdk

The macOS, iOS and Windows SDKs, laid out to cross-compile from Linux. There's one directory per platform and one subdirectory per SDK version.

| Directory | SDK |
|---|---|
| `macos/27.0/` | macOS 27.0 SDK (Xcode 27.0, 27A266a), with arm64 and x86_64 libraries |
| `ios/27.0/` | iPhoneOS and iPhoneSimulator 27.0 SDKs (Xcode 27.0) |
| `windows/10.0.28000/` | Windows SDK 10.0.28000.0, MSVC 14.50.35717, DIA SDK |

`windows/10.0.28000/win_toolchain.json` gives absolute paths under `/data/zsdk/windows/10.0.28000`. Clone this repository to `/data/zsdk`, or change those paths.

## Licence

The Apple SDKs belong to Apple. The Visual Studio and Windows SDK files belong to Microsoft. Each is subject to its owner's licence terms. They're provided for development and testing only, not for commercial use.
