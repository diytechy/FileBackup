#!/usr/bin/env python3
"""Window-placement / window-count experiment.

Ground truth is the REALISED 7-Zip ratio already in the store (stored bytes over
manifest Length), so a sampling scheme is graded on how well it predicts what
actually happened -- not on how well it agrees with the current probe.

The sampling compressor here is zlib level 1, NOT the probe's Brotli(Fastest):
the hub has no brotli and this is a production box that will not be modified for
an experiment. That is a real limitation and it is bounded -- the question asked
is WHERE to sample and HOW MANY, which is about how compressibility varies
across a file's offsets. Both are fast entropy coders with a ~32 KiB window; the
absolute ratios differ, the ranking across offsets is what is being measured.
"""
import csv, os, random, sys, zlib

B = "/mnt/backup-drive/library"
WIN = 262144          # match CompressProbeSampleBytes
NOFF = 21             # offsets 0.00 .. 1.00 in 5% steps
MINLEN = 32 * 1024 * 1024
TARGET = 200

# ---- realised ratio from manifest + one pool listing (no journal, no stats) ---
# NOTE: an earlier version did os.scandir(B) + e.stat() over all 159,771 pool
# entries -- which is precisely the 160k-stat storm over FUSE that C-1 of the
# stat-storm review is about, and it was just as slow here. Parse the manifest
# FIRST, filter to candidates, and stat only those: a few thousand, not 160k.
rows = []
cand = []
with open(os.path.join(B, "MANIFEST.csv"), newline="") as fh:
    for r in csv.reader(fh):
        if len(r) < 6 or r[0] == "DataPath":
            continue
        dp, rel, ln, comp = r[0], r[1], r[2], r[5]
        if comp != "Yes" or not dp:
            continue
        try:
            ln = int(ln)
        except ValueError:
            continue
        if ln < MINLEN:
            continue
        cand.append((rel, ln, dp))

sys.stderr.write("candidates before stat: %d\n" % len(cand))
for rel, ln, dp in cand:
    try:
        rows.append((rel, ln, os.stat(os.path.join(B, dp)).st_size / ln))
    except OSError:
        pass

# ---- stratify by realised ratio so both ends of the outcome are represented ---
bands = {}
for rel, ln, r in rows:
    bands.setdefault(min(int(r * 10), 9), []).append((rel, ln, r))
random.seed(20260907)
sample, per = [], max(1, TARGET // max(1, len(bands)))
for b in sorted(bands):
    random.shuffle(bands[b])
    sample += bands[b][:per]
sys.stderr.write("candidates=%d  bands=%s  sample=%d\n" %
                 (len(rows), {b: len(v) for b, v in sorted(bands.items())}, len(sample)))

# ---- sample each file at NOFF evenly spaced offsets ---------------------------
out = csv.writer(sys.stdout)
out.writerow(["rel", "length", "realised"] + ["r%02d" % i for i in range(NOFF)])
done = 0
for rel, ln, realised in sample:
    path = os.path.join("/srv/library", rel)
    try:
        ratios = []
        with open(path, "rb", buffering=0) as f:
            span = ln - WIN
            for i in range(NOFF):
                f.seek(int(span * i / (NOFF - 1)))
                buf = f.read(WIN)
                if not buf:
                    ratios = []
                    break
                ratios.append(len(zlib.compress(buf, 1)) / len(buf))
        if len(ratios) != NOFF:
            continue
    except OSError:
        continue
    out.writerow([rel, ln, "%.4f" % realised] + ["%.4f" % x for x in ratios])
    done += 1
    if done % 25 == 0:
        sys.stderr.write("  %d/%d\n" % (done, len(sample)))
sys.stderr.write("sampled %d files\n" % done)
