#!/usr/bin/env python3
"""Private real-file corpus and repeatable native/independent-recovery measurements."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil

from measure_native import measure


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path, help='fresh absolute private fixture; never deleted')
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--files', type=int, default=3000)
    parser.add_argument('--large-mib', type=int, default=64)
    parser.add_argument('--large-file-mib', type=int, default=8)
    parser.add_argument('--compressible', action='store_true', help='repeated large-file payload; small files stay distinct/random')
    parser.add_argument('--compress', action='store_true')
    parser.add_argument('--seconds', type=int, default=1800)
    args = parser.parse_args()
    root = args.root
    if not root.is_absolute() or root.exists() or not 1 <= args.files <= 1_000_000 or not 0 <= args.large_mib <= 8192 or not 1 <= args.large_file_mib <= 8192 or args.seconds <= 0:
        parser.error('fresh absolute root required; 1..1M small files; 0..8192 large MiB')
    binary = str(args.binary.resolve(strict=True))
    if os.name == 'nt' and not shutil.which('pwsh'):
        parser.error('PowerShell 7 is required to measure independent Windows recovery')
    required = 4 * (args.files * 8192 + args.large_mib * 1048576) + 5 * 1024**3
    ancestor = root.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    if shutil.disk_usage(ancestor).free < required:
        parser.error('insufficient free space for corpus, store, two restores and 5 GiB reserve')
    source = root / 'source'
    source.mkdir(parents=True)
    rng = random.Random(20261106)
    expected = {}
    for n in range(args.files):
        path = source / f'd{n // 500:05}' / f'file-{n:07}.bin'
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(rng.randbytes(4096))
        expected[path.relative_to(source).as_posix()] = digest(path)
    repeated = (b'FileBackup performance recovery\n' * 40000)[:1048576]
    for n in range(0, args.large_mib, args.large_file_mib):
        path = source / f'large-{n:05}.bin'
        compressible_chunk = f'{n:016x}'.encode() + repeated[16:]
        with path.open('xb') as stream:
            for _ in range(min(args.large_file_mib, args.large_mib-n)):
                stream.write(compressible_chunk if args.compressible else rng.randbytes(1048576))
        expected[path.name] = digest(path)
    config = root / 'config.json'
    config.write_text(json.dumps({'ConfigVersion': 3, 'BackupSets': [{
        'Name': 'performance', 'SourcePath': str(source), 'StorePath': str(root/'store'),
        'CompressEnabled': args.compress, 'HashRecalcFreq': 'N', 'BrowseView': 'off'}]}), encoding='utf-8')
    (root/'corpus.json').write_text(json.dumps(dict(small_files=args.files, large_mib=args.large_mib,
        distinct_contents=len(set(expected.values())), large_file_mib=args.large_file_mib,
        compressible=args.compressible, source_bytes=args.files*4096+args.large_mib*1048576,
        expected_sha256=expected), indent=2), encoding='utf-8')

    def run(label, command):
        result = measure(command, root/f'{label}.json', label, seconds=args.seconds, cores=4)
        if result['exit_code'] or result['stopped'] or result['measurement_errors']:
            raise RuntimeError(f'{label} failed/stopped; inspect {root}')
        if label.startswith('unchanged-'):
            report = json.loads((root/f'{label}.stdout').read_text())
            if report['reused'] != len(expected) or any(report[k] for k in ('captured', 'added', 'changed', 'removed', 'failed', 'frozen')):
                raise RuntimeError(f'{label} was not an unchanged run')

    for label, action in [('capture', 'backup'), ('unchanged-1', 'backup'), ('unchanged-2', 'backup'), ('verify', 'verify')]:
        run(label, [binary, action, '--config', str(config), '--no-mail'] + (['--deep'] if action == 'verify' else []))
    kit = root/'store/CurrentBackup'
    routes = []
    if shutil.which('pwsh'):
        routes.append(('powershell', ['pwsh', '-NoProfile', '-File', str(kit/'RECONSTRUCT.ps1'), '-ExitCode', '-TargetRoot']))
    if os.name != 'nt':
        routes.append(('bash', ['bash', str(kit/'reconstruct.sh'), '--target-root']))
    for label, command in routes:
        target = root/f'restored-{label}'
        run(f'restore-{label}', command+[str(target)])
        actual = {p.relative_to(target).as_posix(): digest(p) for p in target.rglob('*') if p.is_file()}
        if actual != expected:
            raise RuntimeError(f'{label} byte/path comparison failed')
        (root/f'{label}-comparison.json').write_text(json.dumps(dict(files=len(actual), sha256_equal=True)), encoding='utf-8')
    print(f'Corpus and checks complete: {root}', flush=True)


if __name__ == '__main__':
    main()
