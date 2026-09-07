#!/usr/bin/env python3
"""Grade window placements and counts against the realised 7-Zip ratio."""
import csv, statistics as st, sys

rows = []
with open("/tmp/win.csv", newline="") as fh:
    rd = csv.reader(fh); hdr = next(rd)
    for r in rd:
        rows.append((r[0], int(r[1]), float(r[2]), [float(x) for x in r[3:]]))
N = len(rows[0][3])
print("files=%d  offsets=%d\n" % (len(rows), N))

def corr(a, b):
    ma, mb = st.mean(a), st.mean(b)
    num = sum((x-ma)*(y-mb) for x, y in zip(a, b))
    da = sum((x-ma)**2 for x in a) ** 0.5
    db = sum((y-mb)**2 for y in b) ** 0.5
    return num/(da*db) if da and db else 0.0

real = [r[2] for r in rows]

print("== per-offset: how well does ONE window at this position predict the outcome ==")
print("  pos   corr    MAE   mean_ratio")
percorr = []
for i in range(N):
    col = [r[3][i] for r in rows]
    c = corr(col, real)
    mae = st.mean(abs(x-y) for x, y in zip(col, real))
    percorr.append((c, i))
    if i % 2 == 0 or i in (1, N-2):
        print("  %3d%%  %+.3f  %.3f   %.3f" % (i*100//(N-1), c, mae, st.mean(col)))
best = sorted(percorr, reverse=True)[:5]
print("\n  best single offsets by correlation: " +
      ", ".join("%d%% (r=%.3f)" % (i*100//(N-1), c) for c, i in best))

def grade(idxs, label):
    preds = [st.median([r[3][i] for i in idxs]) for r in rows]
    mae = st.mean(abs(p-x) for p, x in zip(preds, real))
    c = corr(preds, real)
    # decision quality at the shipped threshold: compress iff predicted <= 0.90
    tp = fp = tn = fn = 0
    for p, x in zip(preds, real):
        pc, ac = (p <= 0.90), (x <= 0.90)      # predicted-worth-it, actually-worth-it
        if pc and ac: tp += 1
        elif pc and not ac: fp += 1            # compressed for nothing
        elif not pc and ac: fn += 1            # missed a real win
        else: tn += 1
    print("  %-30s MAE=%.3f corr=%+.3f  wasted=%3d missed=%3d" % (label, mae, c, fp, fn))

print("\n== window COUNT: median of N evenly spaced windows ==")
for n in (1, 3, 5, 7, 9, 11, 21):
    idxs = [round(i*(N-1)/(n-1)) for i in range(n)] if n > 1 else [(N-1)//2]
    grade(idxs, "N=%-2d %s" % (n, [round(i*100/(N-1)) for i in idxs]))

print("\n== window PLACEMENT: 3 windows, current vs alternatives ==")
grade([0, (N-1)//2, N-1],      "current 0/50/100%")
grade([2, (N-1)//2, N-3],      "inset 10/50/90%")
grade([4, (N-1)//2, N-5],      "inset 20/50/80%")
grade([5, 10, 15],             "interior 25/50/75%")
grade([b[1] for b in best[:3]],"best-3 by corr")

print("\n== dropping the endpoints entirely ==")
grade([i for i in range(1, N-1)],        "all interior (5..95%)")
grade([i for i in range(N)],             "all 21 incl endpoints")
