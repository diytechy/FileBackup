#!/usr/bin/env python3
"""Build-time provisioning only; no backup or recovery path downloads dependencies."""
import argparse
import hashlib
from pathlib import Path
import urllib.request
import zipfile

VERSION = "8.0.0"
SHA256 = "b33386b744cd068e9d11d0b781fe87f9ef585b7370d30a1ae949c218618ae5c1"
URL = f"https://api.nuget.org/v3-flatcontainer/system.io.hashing/{VERSION}/system.io.hashing.{VERSION}.nupkg"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--package", type=Path, help="Already downloaded NuGet package for an offline build")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    package = args.package or args.cache / f"system.io.hashing.{VERSION}.nupkg"
    if not package.exists():
        if args.package:
            parser.error("offline package does not exist")
        with urllib.request.urlopen(URL, timeout=60) as response:
            data = response.read(4 * 1024 * 1024 + 1)
        if len(data) > 4 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != SHA256:
            raise SystemExit("Dependency download failed size/digest validation")
        package.write_bytes(data)
    if hashlib.sha256(package.read_bytes()).hexdigest() != SHA256:
        raise SystemExit("NuGet package digest differs from the pinned dependency")
    destination = args.cache / "System.IO.Hashing.dll"
    with zipfile.ZipFile(package) as archive:
        # Extract exactly the declared member, not arbitrary package paths.
        destination.write_bytes(archive.read("lib/netstandard2.0/System.IO.Hashing.dll"))
    print(destination.resolve())

if __name__ == "__main__":
    main()
