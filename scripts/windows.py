#!/usr/bin/env python3
"""Lay out MSVC and the Windows SDK in windows/<version>/, on Linux.

    windows.py add <dir>                     download what <dir>/pins.json pins and lay it out
    windows.py verify <dir>                  check what is laid out is what is pinned (no network)
    windows.py json <dir>                    print the toolchain's description (win_toolchain.json)
    windows.py case-links <dir> [<src>...]   link names spelled in another case (see add_case_links)

Every package is pinned in <dir>/pins.json, by version and SHA-256: the toolchain is the
same whenever and wherever it is laid out, and never what Microsoft's channel
happens to offer that day. Running add accepts Microsoft's licence terms
for Visual Studio and the Windows SDK.

The tree is laid out as depot_tools' packaged Windows toolchain has it
(win_toolchain/package_from_installed.py makes that on a Windows machine):

    vs_files/VC/Tools/MSVC/<version>/    the C++ library, ATL, the x64 tools
    vs_files/VC/Redist/MSVC/<version>/   the C++ runtime's DLLs
    vs_files/DIA SDK/
    vs_files/Windows Kits/10/            Include, Lib, bin, Debuggers, Redist
    vs_files/Windows Kits/10/bin/SetEnv.{x86,x64}.json
    vs_files/sys64                       the runtime's DLLs
    pins.json                            what it is laid out from (load_pins)
    VERSIONS, PINS                       the versions, and each package by version and SHA-256
    downloads/                           the packages (not in the repository)
"""

import hashlib
import json
import os
import pathlib
import re
import shutil
import sys
import urllib.request
import zipfile

NUGET = "https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg"


def load_pins(cache):
    """<dir>/pins.json: what the version is laid out from. Each package of
    Visual Studio by its version, the SHA-256 its manifest gives it, and the
    URL it was served from where that is known (url_base: the manifest's URLs
    are <url_base><SHA-256>/<package>.vsix); one without is looked up by its
    SHA-256 in vs_channel's current manifest, and when that no longer has it,
    the run stops and says so. The Windows SDK's and the debuggers' packages
    come from NuGet. VC/Tools/MSVC/<msvc_dir> is named after the version the
    CRT's headers carry. A new version is a new directory with its own
    pins.json: a toolset is a decision, never what a download happens to get."""
    global SDK_VERSION, VS_YEAR, VS_CHANNEL, MSVC_PREFIX, MSVC_DIR
    global VS_PACKAGES, SDK_PACKAGES, DEBUGGERS_PACKAGE, DEBUGGERS_SHA256
    path = cache / "pins.json"
    if not path.exists():
        raise SystemExit(f"no {path}: write the version's pins first (see windows/*/pins.json)")
    pins = json.loads(path.read_text())
    SDK_VERSION, VS_YEAR, VS_CHANNEL = pins["sdk_version"], pins["vs_year"], pins["vs_channel"]
    MSVC_PREFIX, MSVC_DIR = pins["msvc_prefix"], pins["msvc_dir"]
    VS_PACKAGES = {name: (p["version"], p["sha256"], p["url_base"]) for name, p in pins["vs_packages"].items()}
    # In order: the SDK's package, then its x64 libraries'.
    SDK_PACKAGES = {(p["name"], p["version"]): p["sha256"] for p in pins["sdk_packages"]}
    DEBUGGERS_PACKAGE = (pins["debuggers"]["name"], pins["debuggers"]["version"])
    DEBUGGERS_SHA256 = pins["debuggers"]["sha256"]
    # windows/<version>: the SDK's version without its last field.
    if cache.name != SDK_VERSION.rsplit(".", 1)[0]:
        raise SystemExit(f"{path} pins the Windows SDK {SDK_VERSION}, not one for {cache.name}")


def log(message):
    print(f"==> {message}", file=sys.stderr, flush=True)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url, path, sha256):
    if path.exists() and sha256_of(path) == sha256:
        return path
    log(f"fetching {path.name}")
    partial = path.with_name(path.name + ".partial")
    with urllib.request.urlopen(url, timeout=120) as response, open(partial, "wb") as out:
        shutil.copyfileobj(response, out, 1 << 20)
    got = sha256_of(partial)
    if got != sha256:
        partial.unlink()
        raise SystemExit(f"{path.name}: SHA-256 {got}, expected {sha256}")
    partial.rename(path)
    return path


def vs_package_path(downloads, name):
    return downloads / f"{name}-{VS_PACKAGES[name][0]}.vsix"


def vs_packages(downloads):
    """The pinned packages of Visual Studio (VS_PACKAGES), each checked against
    its pinned SHA-256: from downloads/ when they are there, from their pinned
    URL, or found by that SHA-256 in the current manifest."""
    paths, unknown = {}, []
    for name, (version, sha256, base) in sorted(VS_PACKAGES.items()):
        path = vs_package_path(downloads, name)
        if path.exists() and sha256_of(path) == sha256:
            paths[name] = path
        elif base:
            # The manifest's URLs are <base><SHA-256>/<package>.vsix.
            paths[name] = download(f"{base}{sha256}/{name}.vsix", path, sha256)
        else:
            unknown.append(name)
    if not unknown:
        return paths
    with urllib.request.urlopen(VS_CHANNEL, timeout=120) as response:
        channel = json.load(response)
    item = next(i for i in channel["channelItems"] if i["type"] == "Manifest")
    with urllib.request.urlopen(item["payloads"][0]["url"], timeout=300) as response:
        manifest = json.load(response)
    offered = {}
    for package in manifest["packages"]:
        if package["id"] in unknown and package.get("payloads"):
            offered[package["id"]] = package
    gone = []
    for name in unknown:
        version, sha256, _ = VS_PACKAGES[name]
        package = offered.get(name)
        payload = package and package["payloads"][0]
        if not payload or payload["sha256"].lower() != sha256:
            now = package["version"] if package else "none"
            gone.append(f"{name} {version} (the channel has {now})")
            continue
        paths[name] = download(payload["url"], vs_package_path(downloads, name), sha256)
    if gone:
        raise SystemExit(
            "the pinned MSVC packages are not in Visual Studio's channel any more and not in "
            f"{downloads}: {'; '.join(gone)}. A newer toolset is a new version with its own "
            "pins.json, tested by a Windows build.")
    return paths


def verify(cache):
    """What is laid out in cache is what is pinned here; read from the disk
    only. Returns the differences, none when it matches."""
    problems = []
    tree, downloads = cache / "vs_files", cache / "downloads"
    if not (cache / "VERSIONS").exists():
        return [f"no toolchain laid out in {cache}"]
    # What it was laid out from: the packages in downloads/, or, once they
    # have been checked, PINS, which records them, for a cache whose
    # downloads were removed to save the space.
    record = cache / "PINS"
    if record.exists() and not downloads.is_dir():
        if record.read_text() != pins_text():
            problems.append(f"PINS, what the toolchain was laid out from, is not what is pinned now:\n"
                            + record.read_text())
        downloads = None
    for name, (version, sha256, _) in sorted(VS_PACKAGES.items()) if downloads else ():
        path = vs_package_path(downloads, name)
        if not path.exists():
            others = sorted(p.name for p in downloads.glob(f"{name}-*.vsix"))
            problems.append(f"{name}: no {path.name}" + (f" (there is {', '.join(others)})" if others else ""))
        elif sha256_of(path) != sha256:
            problems.append(f"{path.name}: SHA-256 {sha256_of(path)}, pinned {sha256}")
    nuget = [(f"{key[0]}.{key[1]}.nupkg", sha256) for key, sha256 in sorted(SDK_PACKAGES.items())]
    nuget.append((f"{DEBUGGERS_PACKAGE[0]}.{DEBUGGERS_PACKAGE[1]}.nupkg", DEBUGGERS_SHA256))
    for name, sha256 in nuget if downloads else ():
        path = downloads / name
        if not path.exists() or sha256_of(path) != sha256:
            problems.append(f"{name}: missing or not the pinned SHA-256")
    def entries(directory):
        return sorted(p.name for p in directory.iterdir()) if directory.is_dir() else []
    for directory, wanted in ((tree / "VC/Tools/MSVC", MSVC_DIR), (tree / "VC/Redist/MSVC", MSVC_DIR),
                              (tree / "Windows Kits/10/Include", SDK_VERSION),
                              (tree / "Windows Kits/10/Lib", SDK_VERSION)):
        if entries(directory) != [wanted]:
            problems.append(f"{directory.relative_to(cache)} holds {entries(directory) or 'nothing'}, pinned {wanted}")
    versions = cache / "VERSIONS"
    expected = versions_text()
    if not versions.exists() or versions.read_text() != expected:
        problems.append(f"VERSIONS is not {expected!r}")
    if not problems and downloads and (not record.exists() or record.read_text() != pins_text()):
        record.write_text(pins_text())
    return problems


def pins_text():
    """PINS: each package the toolchain is laid out from, by name, version and SHA-256."""
    lines = [f"{name} {version} {sha256}" for name, (version, sha256, _) in sorted(VS_PACKAGES.items())]
    lines += [f"{key[0]} {key[1]} {sha256}" for key, sha256 in sorted(SDK_PACKAGES.items())]
    lines.append(f"{DEBUGGERS_PACKAGE[0]} {DEBUGGERS_PACKAGE[1]} {DEBUGGERS_SHA256}")
    return "\n".join(lines) + "\n"


def versions_text():
    return (f"MSVC {MSVC_DIR} ({MSVC_PREFIX[:-1]})\n"
            f"Windows SDK {SDK_VERSION} ({' '.join(k[1] for k in SDK_PACKAGES)})\n"
            f"Debuggers {DEBUGGERS_PACKAGE[1]}\n")


def unzip(archive, root, rename):
    """Extract what rename() gives a path under root for, and refuse any path
    that would leave root."""
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            name = urllib.request.unquote(info.filename)
            relative = rename(name)
            if relative is None:
                continue
            target = (root / relative).resolve()
            if root.resolve() not in target.parents:
                raise SystemExit(f"{archive.name}: {name} leaves the tree")
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(info) as source, open(target, "wb") as out:
                shutil.copyfileobj(source, out, 1 << 20)


def set_env(root, msvc):
    """The Windows Kits/10/bin/SetEnv.<cpu>.json of package_from_installed.py,
    which setup_toolchain.py reads."""
    kit = ["Windows Kits", "10"]
    vc = ["VC", "Tools", "MSVC", msvc]
    common = {
        "VSINSTALLDIR": [[".\\"]],
        "VCINSTALLDIR": [["VC\\"]],
        "INCLUDE": [
            kit + ["Include", SDK_VERSION, "um"],
            kit + ["Include", SDK_VERSION, "shared"],
            kit + ["Include", SDK_VERSION, "winrt"],
            kit + ["Include", SDK_VERSION, "ucrt"],
            vc + ["include"],
            vc + ["atlmfc", "include"],
        ],
        "LIBPATH": [vc + ["lib", "x86", "store", "references"], kit + ["UnionMetadata", SDK_VERSION]],
        "VCToolsInstallDir": [vc[:-1] + [msvc + os.path.sep]],
    }
    for cpu in ("x86", "x64"):
        env = dict(common)
        env["PATH"] = [kit + ["bin", SDK_VERSION, "x64"], vc + ["bin", "HostX64", "x64"]]
        env["LIB"] = [
            vc + ["lib", cpu],
            kit + ["Lib", SDK_VERSION, "um", cpu],
            kit + ["Lib", SDK_VERSION, "ucrt", cpu],
            vc + ["atlmfc", "lib", cpu],
        ]
        # GN declares the x86 toolchain beside x64 and setup_toolchain.py
        # wants its directories to exist. Nothing in the engine builds for it,
        # so its libraries are not fetched.
        for parts in env["LIB"] + common["LIBPATH"]:
            (root.joinpath(*parts)).mkdir(parents=True, exist_ok=True)
        (root.joinpath(*kit, "bin")).mkdir(parents=True, exist_ok=True)
        with open(root.joinpath(*kit, "bin", f"SetEnv.{cpu}.json"), "w") as f:
            json.dump({"env": env}, f, indent=2)


def assemble(cache, downloads, tree):
    sdk, sdk_x64 = (download(NUGET.format(*key), downloads / f"{key[0]}.{key[1]}.nupkg", digest)
                    for key, digest in SDK_PACKAGES.items())
    debuggers = download(
        NUGET.format(*DEBUGGERS_PACKAGE),
        downloads / f"{DEBUGGERS_PACKAGE[0]}.{DEBUGGERS_PACKAGE[1]}.nupkg",
        DEBUGGERS_SHA256,
    )
    vs = vs_packages(downloads)

    log("unpacking")
    if tree.exists():
        shutil.rmtree(tree)

    # Each package of a toolset names its own patch version; clang's
    # /winsysroot looks in one directory, the highest, so they share the CRT's.
    with zipfile.ZipFile(vs[MSVC_PREFIX + "CRT.Headers.base"]) as z:
        msvc = next(
            m.group(1) for m in map(re.compile(r"Contents/VC/Tools/MSVC/([\d.]+)/").match, z.namelist()) if m
        )
    if msvc != MSVC_DIR:
        raise SystemExit(f"the CRT's headers are of MSVC {msvc}, pinned {MSVC_DIR}")

    def vs_path(name):
        if not name.startswith("Contents/"):
            return None
        name = name[len("Contents/"):]
        name = re.sub(r"^VC/Tools/MSVC/[\d.]+/", f"VC/Tools/MSVC/{msvc}/", name)
        name = re.sub(r"^VC/Redist/MSVC/[\d.]+/", f"VC/Redist/MSVC/{msvc}/", name)
        # The packages say Hostx64, and SetEnv and the packaged toolchain HostX64.
        name = name.replace("/bin/Hostx64/", "/bin/HostX64/")
        return name

    for archive in vs.values():
        unzip(archive, tree, vs_path)

    def sdk_path(name):
        if not name.startswith("c/"):
            return None
        tail = name[2:]
        # What the engine has no use for: 100 MiB of documentation and sources,
        # and tools for other machines.
        if re.match(r"(Source|References|DesignTime|Extension SDKs|Platforms)/", tail):
            return None
        if re.match(rf"bin/{re.escape(SDK_VERSION)}/(x86|arm64)/", tail):
            return None
        return f"Windows Kits/10/{tail}"

    unzip(sdk, tree, sdk_path)

    def sdk_lib_path(name):
        m = re.match(r"c/(um|ucrt)/x64/(.+)", name)
        return f"Windows Kits/10/Lib/{SDK_VERSION}/{m[1]}/x64/{m[2]}" if m else None

    unzip(sdk_x64, tree, sdk_lib_path)

    def debuggers_path(name):
        m = re.match(r"content/amd64/(dbghelp|dbgcore|symsrv)\.dll$", name, re.I)
        return f"Windows Kits/10/Debuggers/x64/{m[1]}.dll" if m else None

    unzip(debuggers, tree, debuggers_path)

    for needed in (
        f"VC/Tools/MSVC/{msvc}/include/vector",
        f"VC/Tools/MSVC/{msvc}/atlmfc/include/atlbase.h",
        f"VC/Tools/MSVC/{msvc}/lib/x64/libcmt.lib",
        f"VC/Tools/MSVC/{msvc}/bin/HostX64/x64/cl.exe",
        f"Windows Kits/10/Include/{SDK_VERSION}/um/Windows.h",
        f"Windows Kits/10/Lib/{SDK_VERSION}/ucrt/x64/ucrt.lib",
        "Windows Kits/10/Debuggers/x64/dbghelp.dll",
    ):
        if not (tree / needed).exists():
            raise SystemExit(f"not in the packages: {needed}")

    set_env(tree, msvc)

    # The runtime's DLLs, where the packaged toolchain has them. Only x64 has any.
    redist = next((tree / "VC/Redist/MSVC" / msvc / "x64").glob("Microsoft.VC*.CRT"))
    (tree / "sys64").symlink_to(redist.relative_to(tree))
    (tree / "sys32").mkdir()
    (tree / "sysarm64").mkdir()
    (tree / "wdk").mkdir()

    (cache / "VERSIONS").write_text(versions_text())


INCLUDE = re.compile(rb'^[ \t]*#[ \t]*(?:include|import)[ \t]*[<"]([^">\r\n]+)[">]', re.M)
PRAGMA_LIB = re.compile(rb'#[ \t]*pragma[ \t]+comment[ \t]*\([ \t]*lib[ \t]*,[ \t]*"([^"]+)"', re.I)
GN_LIB = re.compile(rb'"([A-Za-z0-9_.+-]+\.[Ll][Ii][Bb])"')
SOURCE_SUFFIXES = {".h", ".hh", ".hpp", ".hxx", ".inc", ".inl", ".c", ".cc", ".cpp", ".cxx", ".S", ".asm",
                   ".idl", ".rc", ".mm", ".ipp", ".tcc", ".def"}
SKIP_DIRS = {".git", "out", "llvm-build", "rust-toolchain", "node_modules", "test_data", "web_tests", "wpt"}


def wanted_names(sources, tree):
    """Every name an #include, a #pragma comment(lib) or a BUILD.gn asks for."""
    includes, libs = set(), set()
    roots = [*sources, tree]
    for root in roots:
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in SKIP_DIRS]
            for name in files:
                path = os.path.join(directory, name)
                suffix = os.path.splitext(name)[1]
                is_gn = suffix in (".gn", ".gni")
                # The C++ library's headers have no suffix.
                if not (is_gn or suffix in SOURCE_SUFFIXES or root is tree):
                    continue
                if os.path.islink(path):
                    continue
                try:
                    with open(path, "rb") as f:
                        data = f.read()
                except OSError:
                    continue
                if is_gn:
                    libs.update(GN_LIB.findall(data))
                    continue
                if b"#" not in data:
                    continue
                includes.update(INCLUDE.findall(data))
                libs.update(PRAGMA_LIB.findall(data))
    decode = lambda names: {n.decode("latin-1").replace("\\", "/") for n in names}
    return decode(includes), decode(libs)


def names_in(directory, cache={}):
    """A directory's entries by their lower-case name. Nearly every name asked
    for is the sources' own and in no directory here, so this is asked millions
    of times."""
    key = str(directory)
    if key not in cache:
        try:
            cache[key] = {}
            for entry in sorted(os.listdir(directory)):
                cache[key].setdefault(entry.lower(), set()).add(entry)
        except (NotADirectoryError, FileNotFoundError):
            pass
    return cache[key]


def resolve_case(directory, parts):
    """Walk parts down from directory, adding a link wherever a name exists
    only in another case. Returns whether the path now exists."""
    current = directory
    planned = []
    for part in parts:
        if part in ("", "."):
            continue
        spellings = names_in(current).get(part.lower())
        if not spellings:
            return False
        if part in spellings:
            current = current / part
            continue
        real = min(spellings)
        planned.append((current, part, real))
        current = current / real
    for where, link, real in planned:
        (where / link).symlink_to(real)
        names_in(where)[link.lower()].add(link)
    return True


def add_case_links(tree, sources):
    """clang and lld look for a header or library in the case it is named in,
    which works on Windows' file system and not on Linux's. Here each name
    asked for, by the SDK's own headers or the sources given, gets a link in
    that case beside the file. Run again when those sources change."""
    msvc = next((tree / "VC/Tools/MSVC").iterdir())
    kit = tree / "Windows Kits/10"
    include_roots = [kit / "Include" / SDK_VERSION / n for n in ("um", "shared", "winrt", "ucrt", "cppwinrt")]
    include_roots += [msvc / "include", msvc / "atlmfc/include"]
    lib_roots = [kit / "Lib" / SDK_VERSION / "um/x64", kit / "Lib" / SDK_VERSION / "ucrt/x64",
                 msvc / "lib/x64", msvc / "atlmfc/lib/x64"]

    log("reading every source for the names of headers and libraries")
    includes, libs = wanted_names(sources, tree)
    added_before = sum(1 for root in include_roots + lib_roots for _ in walk_links(root))
    for name in sorted(includes):
        parts = name.split("/")
        if ".." in parts or name.startswith("/"):
            continue
        for root in include_roots:
            if resolve_case(root, parts):
                break
    # lld-link adds .lib to a name without a suffix, and every library is
    # also reachable in lower case with a lower-case suffix.
    for root in lib_roots:
        for entry in sorted(os.listdir(root)):
            if entry.lower().endswith(".lib"):
                resolve_case(root, [entry.lower()])
    for name in sorted(libs):
        if "/" in name:
            continue
        for root in lib_roots:
            if resolve_case(root, [name]):
                break
    added = sum(1 for root in include_roots + lib_roots for _ in walk_links(root))
    log(f"links for names in another case: {added} ({added - added_before} new)")


def walk_links(root):
    for directory, subdirs, files in os.walk(root):
        for name in subdirs + files:
            if os.path.islink(os.path.join(directory, name)):
                yield name


def toolchain_json(cache):
    tree = cache / "vs_files"
    return json.dumps({
        "path": str(tree),
        "version": VS_YEAR,
        "win_sdk": str(tree / "Windows Kits/10"),
        "wdk": str(tree / "wdk"),
        "runtime_dirs": [str(tree / "sys64"), str(tree / "sys32"), str(tree / "sysarm64")],
    }, indent=2) + "\n"


def main():
    usage = __doc__.split("\n\n")[1]
    if len(sys.argv) < 3:
        raise SystemExit("usage:\n" + usage)
    command, cache = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
    load_pins(cache)
    if command == "verify":
        problems = verify(cache)
        if problems:
            raise SystemExit(f"{cache} is not the pinned toolchain:\n  " + "\n  ".join(problems))
        log(f"the pinned toolchain: MSVC {MSVC_DIR}, Windows SDK {SDK_VERSION}")
    elif command == "json":
        if verify(cache):
            raise SystemExit(f"no pinned toolchain in {cache}; run: windows.py verify {cache}")
        sys.stdout.write(toolchain_json(cache))
    elif command == "add":
        downloads = cache / "downloads"
        downloads.mkdir(parents=True, exist_ok=True)
        if not (cache / "VERSIONS").exists():
            assemble(cache, downloads, cache / "vs_files")
        problems = verify(cache)
        if problems:
            raise SystemExit("the toolchain laid out is not the pinned one:\n  " + "\n  ".join(problems)
                             + "\n(an older or newer one is never replaced here: lay it out again only by decision)")
        add_case_links(cache / "vs_files", [])
    elif command == "case-links":
        add_case_links(cache / "vs_files", [pathlib.Path(p).resolve() for p in sys.argv[3:]])
    else:
        raise SystemExit("usage:\n" + usage)


if __name__ == "__main__":
    main()
