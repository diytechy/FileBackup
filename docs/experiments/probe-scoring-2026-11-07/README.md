# The probe scoring run, 2026-11-07

This is the release gate in [the native probe fix design §8.1](../../plans/native-probe-fix-design-2026-11-07.md),
run on the real hub. The Owner asked for it to be run ("You can run the scoring check on the hub").

## What ran

- **Script:** `docs/experiments/probe-window-interior.py` as committed at `91c1560`. The copy on the hub had a matching
  sha256, `ac264520…797c55`.
- **Codec:** Brotli quality 1, window 22, from the `brotli` 1.2.1 module. That is the PowerShell probe's own setting, so
  the result **qualifies**.
- **Environment:** a throwaway `python:3.12-slim` container, low CPU priority. The library (`/srv/library`) and the
  store were mounted read-only, and only a scratch folder was writable. The container, the image and the scratch folder
  were removed afterwards, so the hub host was not changed.
- **Ground truth:** the September PowerShell store on Backup-old (`/mnt/backup-old/library`, flat, manifest of
  2026-10-04). It holds 3,356 distinct compressed objects of 2.25 MiB or more, none missing.
- **Graded:** 498 objects, stratified and weighted back to the population. Two were excluded by the size-and-time guard
  (0.4%).
- **Command:** `--manifest /objects/MANIFEST.csv --objects /objects --source /source --budget 10`, from 20:08:14Z to
  20:12:11Z.

## Result

**Winner: the mean of seven interior windows.** It is the only seven-window combination within the 10% budget, and it
is also the shipped default, so the code does not change.

| Rule | Correlation | Wasted GiB | Forgone GiB | 7-Zip input GiB |
|---|---|---|---|---|
| Old probe: start, middle and end, mean | +0.858 | 444.0 | 0.00 | 575.7 |
| **Seven interior windows, mean** | **+0.958** | **0.0** | **4.30 (7.9%)** | **106.6** |
| Seven interior windows, trimmed mean | +0.954 | 0.0 | 8.63 (15.8%) | 83.1 |
| Seven interior windows, median | +0.942 | 0.0 | 14.82 (27.1%) | 64.5 |

- **Wasted** is 7-Zip input spent on files that saved less than 10%.
- **Forgone** is saving given up on files that did save 10% or more. The saving available was 54.67 GiB.

## The named files

| File | Old probe | Seven interior windows, mean |
|---|---|---|
| The hub's ESB AVCHD `.iso` | 0.332, compress | 0.913, raw |
| The ROTJ `.mkv` | 0.752, compress | 0.996, raw |

The ESB `.mkv` named in the brief was gone from the library by the time of the run, so it could not be read.

## Files

| File | Holds |
|---|---|
| `score.txt` | stderr: the strata, every table and the selection |
| `files.txt` | the `--file` verdicts |
| `windows.csv` | the 41 window ratios per graded object, by cohort, band, length and realised ratio, with no paths |
