#!/usr/bin/env python3
"""Sample simultaneous process-tree RSS; install requirements-performance.txt first."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

import psutil


def measure(command, output, label, rss_limit=1_900_000_000, seconds=1800, cores=None):
    """Shared by the CLI and corpus runner. Never add independent process peaks."""
    output = Path(output)
    paths = [output, output.with_suffix('.stdout'), output.with_suffix('.stderr')]
    if any(path.exists() for path in paths):
        raise FileExistsError(f'Refusing to overwrite measurement: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    affinity = original = None
    parent = psutil.Process()
    if cores:
        original = parent.cpu_affinity()
        if len(original) < cores:
            raise ValueError('Requested core count exceeds available affinity')
        affinity = original[:cores]
        parent.cpu_affinity(affinity)
    started = time.monotonic()
    known = {}
    peak = samples = max_processes = 0
    stopped = None
    errors = set()
    try:
        with paths[1].open('xb') as stdout, paths[2].open('xb') as stderr:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
            try:
                try:
                    root = psutil.Process(process.pid)
                    known[(root.pid, root.create_time())] = root
                except psutil.NoSuchProcess:
                    pass
                while process.poll() is None:
                    # Retain observed identities after reparenting. Processes
                    # born and exited between samples may be missed.
                    for item in list(known.values()):
                        try:
                            for child in item.children(recursive=True):
                                known[(child.pid, child.create_time())] = child
                        except psutil.NoSuchProcess:
                            pass
                        except psutil.AccessDenied:
                            errors.add('child enumeration denied')
                    total = count = 0
                    for key, item in list(known.items()):
                        try:
                            if not item.is_running() or item.status() == psutil.STATUS_ZOMBIE:
                                del known[key]
                                continue
                            total += item.memory_info().rss
                            count += 1
                        except psutil.NoSuchProcess:
                            del known[key]
                        except psutil.AccessDenied:
                            errors.add('RSS query denied')
                    samples += 1
                    max_processes = max(max_processes, count)
                    peak = max(peak, total)
                    if total > rss_limit or time.monotonic() - started > seconds:
                        stopped = 'rss_limit' if total > rss_limit else 'elapsed_limit'
                        break
                    try:
                        process.wait(timeout=0.05)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                elapsed = time.monotonic() - started
                running = process.poll() is None
                # Observed descendants remain ours even if the parent exited.
                # A stopped probe must not leave background work skewing the next one.
                for item in reversed(list(known.values())):
                    try:
                        if item.is_running() and item.status() != psutil.STATUS_ZOMBIE:
                            if not running:
                                errors.add('descendant survived operation exit')
                            item.kill()
                    except psutil.NoSuchProcess:
                        pass
                    except psutil.AccessDenied:
                        errors.add('observed process cleanup denied')
                if running:
                    process.kill()
                process.wait(timeout=10)
    finally:
        if original is not None:
            parent.cpu_affinity(original)
    if samples == 0 or peak == 0:
        errors.add('operation ended without a usable RSS sample')
    result = dict(label=label, command=command, elapsed_seconds=round(elapsed, 3),
                  peak_rss_bytes=peak, exit_code=process.returncode, stopped=stopped,
                  samples=samples, max_simultaneous_processes=max_processes,
                  measurement_errors=sorted(errors), cpu_affinity=affinity,
                  scope='sampled simultaneous RSS of operation and observed descendants; shared pages counted per process; 50 ms interval; short-lived children may be missed; cache state uncontrolled',
                  host=dict(platform=os.name, logical_cpus=psutil.cpu_count(),
                            available_memory_bytes=psutil.virtual_memory().available),
                  psutil_version=psutil.__version__)
    with output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--label', required=True)
    parser.add_argument('--rss-limit', type=int, default=1_900_000_000)
    parser.add_argument('--seconds', type=int, default=1800)
    parser.add_argument('--cores', type=int)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or args.rss_limit <= 0 or args.seconds <= 0 or (args.cores is not None and args.cores <= 0):
        parser.error('command and positive limits required')
    result = measure(command, args.output, args.label, args.rss_limit, args.seconds, args.cores)
    raise SystemExit(0 if result['exit_code'] == 0 and result['stopped'] is None and not result['measurement_errors'] else 1)


if __name__ == '__main__':
    main()
