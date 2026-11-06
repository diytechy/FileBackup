#!/usr/bin/env python3
"""Assemble a private native preview and exact third-party notices; no publishing."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--target", help="Rust target triple; defaults to the build host")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output directory already exists; choose a fresh directory")
    target = args.target or next(line.split(": ", 1)[1] for line in subprocess.check_output(["rustc", "-vV"], text=True).splitlines() if line.startswith("host: "))
    metadata = json.loads(subprocess.check_output(["cargo", "metadata", "--locked", "--format-version", "1", "--filter-platform", target, "--manifest-path", str(ROOT / "rust/Cargo.toml")]))
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    active = set()
    pending = [metadata["resolve"]["root"]]
    while pending:
        item = pending.pop()
        if item in active:
            continue
        active.add(item)
        pending.extend(dep["pkg"] for dep in nodes[item]["deps"])
    # Generate all notices before publishing the artifact directory.
    inventory = []
    notices = {}
    for package in metadata["packages"]:
        if package["name"] == "filebackup" or package["id"] not in active:
            continue
        home = Path(package["manifest_path"]).parent
        candidates = set()
        for pattern in ("LICENSE*", "LICENCE*", "COPYING*", "NOTICE*", "COPYRIGHT*", "UNLICENSE*", "license*", "LICENSES/*"):
            candidates.update(p for p in home.glob(pattern) if p.is_file())
        if package.get("license_file"):
            candidates.add(home / package["license_file"])
        if not candidates:
            raise SystemExit(f"Missing license text for {package['name']} {package['version']}; packaging refused")
        name = package["name"] + "-" + package["version"]
        inventory.append({"component": name, "license": package.get("license"), "source": package.get("source"), "target": target})
        for path in sorted(candidates):
            relative = path.relative_to(home).as_posix().replace("/", "_")
            notices[f"notices/{name}/{relative}"] = path.read_bytes()
    args.output.mkdir(parents=True)
    shutil.copy2(args.binary, args.output / args.binary.name)
    for source, destination in (("docs/native-usage.md", "README.md"), ("docs/native-support.md", "native-support.md"), ("recovery/THIRD-PARTY-NOTICES.txt", "RECOVERY-NOTICES.txt")):
        shutil.copy2(ROOT / source, args.output / destination)
    support = args.output / "native-support.md"
    text = support.read_text(encoding="utf-8")
    for label, filename in (("implementation workorder", "implementation-workorder.md"), ("implementation bindings", "implementation-map.md")):
        text = text.replace(f"[{label}](plans/native-design-2026-11-05/{filename})", f"{label} in the source repository")
    support.write_text(text, encoding="utf-8")
    for relative, data in notices.items():
        target = args.output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (args.output / "components.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
    (args.output / "PROJECT-LICENSE.txt").write_text("This repository has not designated a project redistribution license.\nThis preview is for authorized use; third-party notices do not grant a license to FileBackup itself.\n", encoding="utf-8")
    files = sorted(p for p in args.output.rglob("*") if p.is_file())
    (args.output / "SHA256SUMS").write_text("".join(hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.relative_to(args.output).as_posix() + "\n" for p in files), encoding="utf-8")
    archive = args.output.with_suffix(".zip")
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as out:
        for path in sorted(args.output.rglob("*")):
            if path.is_file():
                out.write(path, path.relative_to(args.output))
    print(archive.resolve())

if __name__ == "__main__":
    main()
