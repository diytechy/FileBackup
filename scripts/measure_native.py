#!/usr/bin/env python3
"""Measure a local process's RSS and elapsed time; no performance acceptance inference."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import subprocess
import time


def resident(process):
    if os.name == "nt":
        class Counters(ctypes.Structure):
            _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong)] + [
                (name, ctypes.c_size_t) for name in (
                    "peak_working", "working", "peak_paged", "paged",
                    "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile")]
        data = Counters()
        data.cb = ctypes.sizeof(data)
        query = ctypes.windll.psapi.GetProcessMemoryInfo
        query.argtypes = [ctypes.c_void_p, ctypes.POINTER(Counters), ctypes.c_ulong]
        if query(int(process._handle), ctypes.byref(data), data.cb):
            return data.working, data.peak_working
    else:
        try:
            values = dict(line.split(":", 1) for line in Path(f"/proc/{process.pid}/status").read_text().splitlines() if ":" in line)
            return int(values["VmRSS"].split()[0]) * 1024, int(values["VmHWM"].split()[0]) * 1024
        except (OSError, KeyError):
            pass
    return 0, 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--label", required=True)
    parser.add_argument("--rss-limit", type=int, default=1_900_000_000)
    parser.add_argument("--seconds", type=int, default=1800)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required after --")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    peak = 0
    stopped = None
    with args.output.with_suffix(".stdout").open("xb") as stdout, args.output.with_suffix(".stderr").open("xb") as stderr:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
        while process.poll() is None:
            current, high = resident(process)
            peak = max(peak, current, high)
            if peak > args.rss_limit or time.monotonic() - start > args.seconds:
                stopped = "rss_limit" if peak > args.rss_limit else "elapsed_limit"
                process.kill()
                break
            time.sleep(0.05)
        process.wait()
        peak = max(peak, resident(process)[1])
    result = {"label": args.label, "command": command, "elapsed_seconds": round(time.monotonic() - start, 3),
              "peak_rss_bytes": peak, "exit_code": process.returncode, "stopped": stopped,
              "scope": "single process only; child RSS not counted; cache state uncontrolled"}
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, indent=2)
        output.write("\n")
    print(json.dumps(result))
    raise SystemExit(0 if process.returncode == 0 and stopped is None else 1)


if __name__ == "__main__":
    main()
