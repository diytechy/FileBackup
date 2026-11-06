#!/usr/bin/env python3
"""Provision a pinned official console helper at build/package time, never runtime."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

VERSION = "26.05"
BASE = f"https://github.com/ip7z/7zip/releases/download/{VERSION}/"
# Digests published in the official GitHub release asset metadata.
ASSETS = {
    "7z2605-extra.7z": "f27a8f103c84785026edcba1f67faf1357225df9d19ddb0b7760d55947141bc7",
    "7z2605-linux-x64.tar.xz": "22cf82fcc6eb7474f1d5bb4f02c0f8ebd573a718089d6833dc30f8350a3b232e",
    "7z2605-linux-arm64.tar.xz": "0b71f6cfc34669b3bf69f2347efd3429f77020665003a13b9cdc53b784270421",
    "7z2605-mac.tar.xz": "12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570",
    "7z2605-src.tar.xz": "0b6080b8c3e7a579161d2d495224c0e51c467576cb4c7048b0ab485ef44cc22e",
}
TARGETS = {
    "x86_64-pc-windows-msvc": ("7z2605-extra.7z", "x64/7za.exe", "7za.exe"),
    "aarch64-pc-windows-msvc": ("7z2605-extra.7z", "arm64/7za.exe", "7za.exe"),
    "x86_64-unknown-linux-gnu": ("7z2605-linux-x64.tar.xz", "7zzs", "7zz"),
    "aarch64-unknown-linux-gnu": ("7z2605-linux-arm64.tar.xz", "7zzs", "7zz"),
    "x86_64-apple-darwin": ("7z2605-mac.tar.xz", "7zz", "7zz"),
    "aarch64-apple-darwin": ("7z2605-mac.tar.xz", "7zz", "7zz"),
}

def host_target():
    return next(line.split(": ", 1)[1] for line in subprocess.check_output(
        ["rustc", "-vV"], text=True).splitlines() if line.startswith("host: "))

def asset(cache, name, offline=False):
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / name
    if path.exists():
        data = path.read_bytes()
    elif offline:
        raise ValueError(f"Offline cache missing {name}")
    else:
        with urllib.request.urlopen(BASE + name, timeout=60) as response:
            data = response.read(8 * 1024 * 1024 + 1)
    if len(data) > 8 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != ASSETS[name]:
        raise ValueError(f"Pinned 7-Zip digest/size check failed: {name}")
    if not path.exists():
        path.write_bytes(data)
    return path

def tar_member(path, member):
    with tarfile.open(path) as archive:
        info = archive.getmember(member)
        if not info.isfile() or info.size > 8 * 1024 * 1024:
            raise ValueError(f"Invalid archive member: {member}")
        return archive.extractfile(info).read()

def provision(cache, output, target, offline=False):
    if target not in TARGETS:
        raise ValueError(f"No pinned 7-Zip helper for {target}")
    name, member, executable = TARGETS[target]
    package = asset(cache, name, offline)
    source = asset(cache, "7z2605-src.tar.xz", offline)
    if name.endswith(".7z"):
        bootstrap = shutil.which("7z") or shutil.which("7zz")
        if not bootstrap and Path("C:/Program Files/7-Zip/7z.exe").is_file():
            bootstrap = "C:/Program Files/7-Zip/7z.exe"
        if not bootstrap:
            raise ValueError("Build-time 7z/7zz is needed to unpack the Windows helper")
        data = subprocess.check_output([bootstrap, "e", "-so", str(package.resolve()), member], timeout=60)
        binary_license = subprocess.check_output([bootstrap, "e", "-so", str(package.resolve()), "License.txt"], timeout=60)
    else:
        data = tar_member(package, member)
        binary_license = tar_member(package, "License.txt")
    output.mkdir(parents=True, exist_ok=True)
    binary = output / executable
    binary.write_bytes(data)
    binary.chmod(0o755)
    (output / "License.txt").write_bytes(binary_license)
    (output / "Source-License.txt").write_bytes(tar_member(source, "DOC/License.txt"))
    for name in ("copying.txt", "unRarLicense.txt"):
        (output / name).write_bytes(tar_member(source, "DOC/" + name))
    shutil.copyfile(source, output / source.name)
    (output / "README.txt").write_text(
        f"FileBackup includes unmodified 7-Zip {VERSION} ({target}).\n"
        "Copyright Igor Pavlov. Licensed under GNU LGPL with the additional terms\n"
        "in License.txt; see copying.txt. https://www.7-zip.org/\n"
        f"Corresponding source is included in {source.name}.\n"
        f"Official binary archive: {BASE}{package.name}\n"
        f"Archive SHA256: {ASSETS[package.name]}\n", encoding="utf-8")
    return {"component": f"7-Zip-{VERSION}", "license": "See tools/7zip/License.txt",
            "source": BASE + source.name, "target": target,
            "archive_sha256": ASSETS[package.name], "binary_sha256": hashlib.sha256(data).hexdigest()}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target", default=None)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    provision(args.cache, args.output, args.target or host_target(), args.offline)
    print(args.output.resolve())

if __name__ == "__main__":
    main()
