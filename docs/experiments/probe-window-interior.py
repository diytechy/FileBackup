#!/usr/bin/env python3
"""Score candidate probe rules against realised 7-Zip ratios. Read-only.

Follows probe-window-sampler.py / probe-window-analyse.py (2026-09-07) and the
native probe design (docs/plans/native-probe-fix-design-2026-11-07.md). It reads
a store's manifest, takes the DISTINCT stored-compressed objects (their realised
ratio is known), samples one source file per object at 41 offsets (every 2.5%
of length - 256 KiB) and grades each rule by its decision at 0.90:

  wasted   7-Zip input spent on objects that realised > 0.90
  forgone  saving given up on objects that realised <= 0.90 but the rule stores raw
  7z-in    7-Zip input the rule would spend

Ground-truth guard: a source file is sampled only if its size equals the
manifest Length and its modification time matches LastWriteTimeStr (within 2 s),
both before and after sampling. Anything else is EXCLUDED and counted, so a
file edited since it was stored never borrows another version's outcome. This
is a size-and-time check, not a hash: treat results as strong evidence, not proof.

The sample is stratified by realised ratio (tenths) and by size cohort; every
statistic, correlation included, is weighted back to the candidate population,
and per-stratum coverage is printed. Strata with no graded object are reported,
not silently dropped.

"shipped" grades today's start/middle/end GEOMETRY under each combination; it is
not a replay of the Rust engine's single 7-Zip run over the joined windows.

It opens files for reading only and writes nothing but stdout (CSV of window
ratios) and stderr (tables). Cost: one manifest read, one stat per candidate
object, then 41 reads of 256 KiB and two stats per sampled file.

  python3 probe-window-interior.py --manifest M --objects O [--sharded] \
      --source S [--target 600] [--file PATH ...] > windows.csv

--sharded: objects live in two-character shard folders (native CurrentBackup);
otherwise flat (the 2026-09 PowerShell store). --file prints, on stderr, the
windows and each rule's verdict for a named file; no manifest needed.
Codec: Brotli quality 1 / window 22 (= .NET CompressionLevel.Fastest, the
PowerShell probe) if the brotli module imports, else zlib level 1. zlib tracks
Brotli closely on real files (corpus 7a) but reads incompressible data slightly
above 1.0 and misses repeats beyond 32 KiB: with zlib, read the results as
placement and combination evidence, not as validation of the 0.90 threshold.
"""
import argparse, csv, os, random, re, sys, zlib
from datetime import datetime, timezone

try:
    import brotli  # type: ignore
    CODEC = "brotli-q1-w22"
    def ratio(buf):
        return len(brotli.compress(buf, quality=1, lgwin=22)) / len(buf)
except ImportError:
    CODEC = "zlib-1"
    def ratio(buf):
        return len(zlib.compress(buf, 1)) / len(buf)

WIN = 256 * 1024
NOFF = 41                         # 0, 2.5, ... 100 %
THRESHOLD = 0.90
MINLEN = 9 * WIN                  # 2.25 MiB: seven windows at eighths stop overlapping
COHORTS = [(MINLEN, 32 * 1024 ** 2, "2.25-32MiB"), (32 * 1024 ** 2, None, ">=32MiB")]

def idx(pct):
    return round(pct / 2.5)

GEOMETRIES = {
    "shipped 0/50/100": [idx(0), idx(50), idx(100)],
    "interior 25/50/75": [idx(25), idx(50), idx(75)],
    "interior 7 (k/8)": [idx(12.5 * k) for k in range(1, 8)],
    "interior 9 (k/10)": [idx(10 * k) for k in range(1, 10)],
}

def mean(xs):
    return sum(xs) / len(xs)

def median(xs):
    s = sorted(xs); n = len(s)
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

def trimmed(xs):
    s = sorted(xs)
    return mean(s[1:-1]) if len(s) > 2 else mean(s)

COMBINERS = {"mean": mean, "median": median, "trimmed": trimmed}

def cohort(length):
    for lo, hi, name in COHORTS:
        if length >= lo and (hi is None or length < hi):
            return name
    return None

def parse_time(text):
    """ISO 8601 with offset and up to 9 fractional digits -> epoch seconds."""
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d+))?(Z|[+-]\d\d:\d\d)?$", text.strip())
    if not m:
        return None
    base = datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")
    tz = m.group(3) or "Z"
    if tz == "Z":
        base = base.replace(tzinfo=timezone.utc)
    else:
        sign = 1 if tz[0] == "+" else -1
        hours, minutes = int(tz[1:3]), int(tz[4:6])
        base = base.replace(tzinfo=timezone.utc)
        base = base.timestamp() - sign * (hours * 3600 + minutes * 60)
        return base + float("0." + (m.group(2) or "0"))
    return base.timestamp() + float("0." + (m.group(2) or "0"))

def unchanged(path, length, stamp):
    st = os.stat(path)
    return st.st_size == length and stamp is not None and abs(st.st_mtime - stamp) <= 2.0

def sample(path, length):
    span = length - WIN
    out = []
    with open(path, "rb", buffering=0) as f:
        for i in range(NOFF):
            f.seek(int(span * i / (NOFF - 1)))
            buf = f.read(WIN)
            if len(buf) != WIN:
                return None
            out.append(ratio(buf))
    return out

def object_path(objects, name, sharded):
    return os.path.join(objects, name[:2].lower(), name) if sharded else os.path.join(objects, name)

def wcorr(pairs):
    """Weighted Pearson correlation of (w, x, y)."""
    sw = sum(w for w, _, _ in pairs)
    if sw <= 0:
        return 0.0
    mx = sum(w * x for w, x, _ in pairs) / sw
    my = sum(w * y for w, _, y in pairs) / sw
    cov = sum(w * (x - mx) * (y - my) for w, x, y in pairs)
    vx = sum(w * (x - mx) ** 2 for w, x, _ in pairs)
    vy = sum(w * (y - my) ** 2 for w, _, y in pairs)
    return cov / (vx * vy) ** 0.5 if vx > 0 and vy > 0 else 0.0

def report_files(paths):
    for path in paths:
        try:
            length = os.path.getsize(path)
            w = sample(path, length) if length >= MINLEN else None
        except OSError as e:
            sys.stderr.write("%s: unreadable (%s)\n" % (path, e))
            continue
        if w is None:
            sys.stderr.write("%s: shorter than 2.25 MiB or unreadable\n" % path)
            continue
        sys.stderr.write("%s length=%d\n" % (path, length))
        for g, ix in GEOMETRIES.items():
            ws = [w[i] for i in ix]
            verdicts = ", ".join("%s=%.3f->%s" % (c, f(ws), "compress" if f(ws) <= THRESHOLD else "raw")
                                 for c, f in COMBINERS.items())
            sys.stderr.write("  %-20s windows=%s  %s\n" % (g, ",".join("%.3f" % x for x in ws), verdicts))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest")
    ap.add_argument("--objects")
    ap.add_argument("--source")
    ap.add_argument("--sharded", action="store_true")
    ap.add_argument("--target", type=int, default=600)
    ap.add_argument("--file", action="append", default=[])
    a = ap.parse_args()
    sys.stderr.write("codec=%s threshold=%.2f\n" % (CODEC, THRESHOLD))
    report_files(a.file)
    if not a.manifest:
        return

    # one candidate per distinct stored object (dedup: one capture compresses it once)
    objects = {}
    with open(a.manifest, newline="", encoding="utf-8") as fh:
        for r in csv.reader(fh):
            if len(r) < 6 or r[0] == "DataPath" or r[5] != "Yes" or not r[0]:
                continue
            try:
                ln = int(r[2])
            except ValueError:
                continue
            if ln >= MINLEN and r[0] not in objects:
                objects[r[0]] = (r[1], ln, parse_time(r[3]))
    strata = {}
    missing = 0
    for dp, (rel, ln, stamp) in objects.items():
        try:
            realised = os.stat(object_path(a.objects, dp, a.sharded)).st_size / ln
        except OSError:
            missing += 1
            continue
        key = (cohort(ln), min(int(realised * 10), 9))
        strata.setdefault(key, []).append((rel, ln, stamp, realised))
    sys.stderr.write("distinct compressed objects >= 2.25 MiB: %d (object missing: %d)\n"
                     % (sum(len(v) for v in strata.values()), missing))

    random.seed(20261107)
    per = max(1, a.target // max(1, len(strata)))
    out = csv.writer(sys.stdout)
    out.writerow(["cohort", "band", "length", "realised"] + ["w%02d" % i for i in range(NOFF)])
    graded, coverage = [], {}
    for key in sorted(strata, key=lambda k: (k[0], k[1])):
        pool = strata[key][:]
        random.shuffle(pool)
        got = excluded = 0
        for rel, ln, stamp, realised in pool:
            if got >= per:
                break
            path = os.path.join(a.source, rel)
            try:
                if not unchanged(path, ln, stamp):
                    excluded += 1
                    continue
                w = sample(path, ln)
                if w is None or not unchanged(path, ln, stamp):
                    excluded += 1
                    continue
            except OSError:
                excluded += 1
                continue
            graded.append((key, ln, realised, w))
            out.writerow([key[0], key[1], ln, "%.4f" % realised] + ["%.4f" % x for x in w])
            got += 1
        coverage[key] = (len(strata[key]), got, excluded)
        sys.stderr.write("  stratum %-10s band %d: population %5d  graded %4d  excluded %4d\n"
                         % (key[0], key[1], len(strata[key]), got, excluded))

    empty = [k for k, (_, g, _) in coverage.items() if g == 0]
    if empty:
        sys.stderr.write("WARNING: %d strata have no graded object and are NOT represented: %s\n"
                         % (len(empty), empty))
    if not graded:
        sys.stderr.write("nothing graded; no table\n")
        return

    weight = {k: coverage[k][0] / coverage[k][1] for k in coverage if coverage[k][1]}
    gib = 1024 ** 3
    for scope in ["all"] + [c[2] for c in COHORTS]:
        rows = [g for g in graded if scope == "all" or g[0][0] == scope]
        if not rows:
            continue
        sys.stderr.write("\n[%s] %d graded, codec %s; population-weighted\n" % (scope, len(rows), CODEC))
        sys.stderr.write("  %-20s %-8s  corr    MAE  wasted GiB  forgone GiB  7z-in GiB\n" % ("geometry", "combine"))
        for gname, ix in GEOMETRIES.items():
            for cname, f in COMBINERS.items():
                pairs, mae_n, mae_d = [], 0.0, 0.0
                wasted = forgone = spent = 0.0
                for key, ln, r, w in rows:
                    p = f([w[i] for i in ix])
                    wt = weight[key]
                    pairs.append((wt, p, r))
                    mae_n += wt * abs(p - r)
                    mae_d += wt
                    if p <= THRESHOLD:
                        spent += wt * ln
                        if r > THRESHOLD:
                            wasted += wt * ln
                    elif r <= THRESHOLD:
                        forgone += wt * ln * (1 - r)
                sys.stderr.write("  %-20s %-8s %+.3f  %.3f  %10.1f  %11.2f  %9.1f\n" %
                                 (gname, cname, wcorr(pairs), mae_n / mae_d,
                                  wasted / gib, forgone / gib, spent / gib))

if __name__ == "__main__":
    main()
