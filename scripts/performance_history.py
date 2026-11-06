#!/usr/bin/env python3
"""Measure 182/364-state unchanged runs on a designated private cardinality fixture."""
import argparse
import datetime
import json
from pathlib import Path
import statistics

from measure_native import measure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--binary', required=True, type=Path)
    parser.add_argument('--with-check', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    marker = json.loads((root/'BENCHMARK.json').read_text())
    config = root/'config.json'
    sets = json.loads(config.read_text())['BackupSets']
    if marker.get('fixture') != 'FileBackup cardinality' or len(sets) != 1 or Path(sets[0]['StorePath']).resolve() != root/'store' or Path(sets[0]['SourcePath']).resolve() != root/'source' or sets[0]['HashRecalcFreq'] != 'N':
        parser.error('only a designated private cardinality fixture is accepted')
    history = root/'store/BackupHistory'
    if any(history.iterdir()):
        parser.error('history must initially be empty; do not rerun on an existing experiment')
    binary = str(args.binary.resolve(strict=True))
    current = root/'store/CurrentBackup'
    # Immutable hard-linked definitions/kits save space. No physical object is
    # copied into history; every state shares the same valid current pool.
    members = [p for p in current.iterdir() if p.is_file() and not p.name.endswith('.prev')]
    timings = {}

    def run(label, action):
        if len(list(history.iterdir())) != count:
            raise RuntimeError(f'{label}: unexpected history count before operation')
        result = measure([binary, action, '--config', str(config), '--no-mail'] + (['--deep'] if action == 'verify' else []), root/f'{label}.json', label, cores=4)
        if result['exit_code'] or result['stopped'] or result['measurement_errors']:
            raise RuntimeError(f'{label} failed/stopped; inspect logs')
        if len(list(history.iterdir())) != count:
            raise RuntimeError(f'{label}: operation changed history count')
        if action == 'backup':
            report = json.loads((root/f'{label}.stdout').read_text())
            if report['reused'] != marker['files'] or any(report[k] for k in ('captured', 'added', 'changed', 'removed', 'failed', 'frozen')):
                raise RuntimeError(f'{label} was not an unchanged run')
        return result

    for n in range(365):
        state = history/(datetime.date(2025, 1, 1)+datetime.timedelta(days=n)).strftime('%Y_%m_%d_00_00_00')
        state.mkdir()
        for member in members:
            (state/member.name).hardlink_to(member)
        count = n+1
        if count in (182, 364):
            run(f'history-{count}-warmup', 'backup')
            timings[str(count)] = [run(f'history-{count}-{trial}', 'backup')['elapsed_seconds'] for trial in range(1, 4)]
    if args.with_check:
        run('history-365-deep-check', 'verify')
    medians = {count: statistics.median(times) for count, times in timings.items()}
    result = dict(files_per_state=marker['files'], distinct_objects=marker['files'], bytes_per_file=8,
                  changed_bytes=0, trials_seconds=timings, median_seconds=medians,
                  ratio_364_over_182=medians['364']/medians['182'],
                  scope='warm uncontrolled caches; hard-linked historical definitions; no reread due; same unchanged source; not full-volume/reference-hardware qualification')
    (root/'history-comparison.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
