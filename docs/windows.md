# Windows SDK sources

Each `windows/<version>/` is laid out from Microsoft's own downloads, each pinned by version and SHA-256 in that version's `pins.json`. This page lists where they come from, so anyone can download them and check them.

## windows/10.0.28000

### The Windows SDK ISO

The Windows SDK 10.0.28000.2270 ISO (June 2026): the release that the NuGet packages in `pins.json` (`microsoft.windows.sdk.cpp` 10.0.28000.2270) come from. Microsoft installs Debugging Tools for Windows (WinDbg, `cdb`, `kd`, `ntsd`) from the SDK's installer ([Debugging Tools for Windows](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/debugger-download-tools)), and the ISO is that installer's offline copy.

| | |
|---|---|
| Listed on | [Windows SDK downloads](https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads), "Windows 11 — 28000 versions", 10.0.28000.2270, "ISO" |
| Link | `https://go.microsoft.com/fwlink/?linkid=2370316` |
| Redirects to (2026-11-25) | `https://download.microsoft.com/download/78b533c3-6724-4e28-a984-b9fa93265781/28000.2270.260609-1642.br_release_svc_im_WindowsSDK.iso` |
| Size | 1,178,042,368 bytes |
| SHA-256 | `1e0cbe0e5fce95c4a29f12c2e9cadf088a22acf38d0cc23f54f06985214712d3` |

Microsoft publishes no checksum for the ISO. The SHA-256 above is of the copy downloaded on 2026-11-25, whose size matched the server's `Content-Length`.

To download and check it:

```sh
curl -fL -C - -o WindowsSDK-10.0.28000.2270.iso 'https://go.microsoft.com/fwlink/?linkid=2370316'
stat -c %s WindowsSDK-10.0.28000.2270.iso    # 1178042368
sha256sum WindowsSDK-10.0.28000.2270.iso     # 1e0cbe0e5fce95c4a29f12c2e9cadf088a22acf38d0cc23f54f06985214712d3
```

On Windows, `Get-FileHash WindowsSDK-10.0.28000.2270.iso -Algorithm SHA256` gives the same digest. Windows can mount the ISO with a double-click. On Linux, `7z x` or `bsdtar -xf` unpacks it, and `mount -o loop` mounts it as root.

### The other packages

The Visual Studio packages (MSVC, ATL, the C++ runtime, the DIA SDK) and the NuGet packages (the Windows SDK's headers and libraries, the debugging engine) are each listed in `windows/10.0.28000/pins.json` with their version and SHA-256. Where it is known, `pins.json` also gives the URL a package was served from. `PINS` lists the same packages, one per line. `mise run add:windows 10.0.28000` downloads them into `windows/10.0.28000/downloads/` and checks each against its pinned SHA-256. Any of them can also be fetched by hand and compared with `sha256sum`.

The NuGet packages are at `https://api.nuget.org/v3-flatcontainer/<name>/<version>/<name>.<version>.nupkg`, with `<name>` in lower case. For example:

```sh
curl -fLO https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.cpp/10.0.28000.2270/microsoft.windows.sdk.cpp.10.0.28000.2270.nupkg
sha256sum microsoft.windows.sdk.cpp.10.0.28000.2270.nupkg   # 0a4887a64d1b17128f9ffd80032f20debabf943f34eea927aac00cc46cb32879
```

Two of the Visual Studio packages, `Tools.HostX64.TargetX64` 14.50.35739 and the DIA SDK 14.51.36257, are no longer served by Visual Studio's channels (see `notes` in `pins.json`).
