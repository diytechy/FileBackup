# WP17 Part B1 — probe codec calibration

Referenced from **LLR-086**. Produced by a throw-away scratch script (not shipped)
that built the corpus below, probed every file with the *same geometry* as
`Measure-SampleCompressibility` (3 windows × 256 KiB at offsets `0`,
`floor((len − 256 KiB)/2)`, `len − 256 KiB`; single whole-file sample under
768 KiB) under both candidate codecs at `CompressionLevel.Fastest`, and compared
each probe decision at threshold `0.10` against the **real whole-file
`7z a -mx=9`** outcome. Run 2026-09-01 on Windows 11 / PowerShell 7 / 7-Zip
`C:\Program Files\7-Zip\7z.exe`.

Ratios are *compressed ÷ original* — **lower is more compressible**; the
decision at threshold 0.10 is `compress` when ratio ≤ 0.90.

## The table

| file | bytes | Deflate probe | Brotli probe | real 7z ‑mx9 | Deflate says | Brotli says | 7z says | Deflate agrees | Brotli agrees |
|---|---:|---:|---:|---:|---|---|---|---|---|
| `genuine-7z.7z` (real `7z -mx=9` archive of text) | 924,905 | 1.05 | 1.00 | 1.00 | raw | raw | raw | ✔ | ✔ |
| `store-mode.zip` (`7z a -tzip -mx=0` of text) | 8,388,766 | 0.28 | 0.19 | 0.11 | compress | compress | compress | ✔ | ✔ |
| `jpeg-concat.jpg` (30 real JPEGs from `C:\Windows\Web`) | 35,742,491 | 0.97 | 0.94 | 0.93 | raw | raw | raw | ✔ | ✔ |
| `video.mkv` (real `SDRSample.mkv`) | 1,813,418 | 1.05 | 1.00 | 1.00 | raw | raw | raw | ✔ | ✔ |
| `video.mp4` (4 real `oobe-intro.mp4` concatenated) | 2,372,244 | 0.48 | 0.46 | 0.89 | compress | compress | compress | ✔ | ✔ |
| `text.txt` (English-like text, 8 MiB) | 8,388,608 | 0.28 | 0.19 | 0.11 | compress | compress | compress | ✔ | ✔ |
| `longrange-1MiB-x16.bin` (1 MiB random block ×16) | 16,777,216 | 1.05 | 1.00 | 0.06 | raw | raw | compress | ✘ | ✘ |
| `longrange-64KiB-x256.bin` (64 KiB random block ×256) | 16,777,216 | 1.05 | 0.25 | 0.00 | raw | compress | compress | ✘ | ✔ |
| `mixed-head.bin` (64 KiB text + 4 MiB random) | 4,259,840 | 0.99 | 0.93 | 0.99 | raw | raw | raw | ✔ | ✔ |
| `mixed-third.bin` (2 MiB random + 2 MiB text + 2 MiB random) | 6,291,456 | 0.80 | 0.73 | 0.71 | compress | compress | compress | ✔ | ✔ |
| `random.bin` (4 MiB CSPRNG) | 4,194,304 | 1.05 | 1.00 | 1.00 | raw | raw | raw | ✔ | ✔ |
| **wrong decisions vs. real 7z** | | **2** | **1** | | | | | | |

Cost (probe wall time for the whole file set, and the `7z -mx=9` seconds the
probe exists to avoid):

| | Deflate | Brotli | `7z -mx=9` |
|---|---:|---:|---:|
| total probe time over the 11 files | 136.8 ms | **27.6 ms** | 7.00 s |

Per-window ratios for the two files that separate the codecs:

| file | Deflate windows | Brotli windows |
|---|---|---|
| `longrange-64KiB-x256.bin` | 1.0546, 1.0546, 1.0546 | 0.2502, 0.2502, 0.2502 |
| `mixed-head.bin` | 0.8602, 1.0545, 1.0547 | 0.7999, 1.0000, 1.0000 |

## The choice: `BrotliStream` at `CompressionLevel.Fastest`

Brotli wins on the stated rule — **fewest wrong decisions vs. the real 7z
outcome** (1 vs. 2) — and would also have won the tie-break, at roughly **one
fifth of Deflate's CPU per sample** (27.6 ms vs. 136.8 ms over the same bytes).

- The decision Deflate gets wrong and Brotli gets right is
  `longrange-64KiB-x256.bin`: a 64 KiB block repeated. Deflate's **32 KiB
  history** cannot see a 64 KiB period *even inside one 256 KiB sample*, so it
  reads pure random (1.05) and stores raw a file `7z` shrinks to nothing.
  Brotli's ~4 MB window catches it (0.25). This is Codex #7's objection,
  reproduced and measured.
- The one decision **both** codecs get wrong, `longrange-1MiB-x16.bin`, is not a
  codec property at all: a 1 MiB period cannot be seen from inside a 256 KiB
  window by *any* codec. It is a limit of **sample size**, recorded here and
  already named in plan §2.2 ("what a sample cannot see is a compressible region
  *between* the offsets") and §7 (scaling the sample count is the deferred
  lever). Its cost is one file stored raw that could have shrunk — a correct
  storage form either way (I-1), never a data risk.
- Deflate's floor of ~1.05 on incompressible input (its 5-byte-per-64 KiB stored
  block overhead) is harmless for the threshold but is why the plan's
  fixture expectations — mixed-head ≈ 0.93, mixed-third ≈ 0.7 — land on
  **Brotli**'s numbers (0.93 / 0.73) rather than Deflate's (0.99 / 0.80).
- Both codecs agree with 7z on every real-world class the defect review named:
  genuine 7-Zip archives, store-mode zip, JPEG, MKV, MP4, text, and both mixed
  files. The codec choice changed exactly one row.

**Determinism note (I-7).** The chosen codec fixes the probe as a pure function
of the bytes *on a given runtime*; a ratio that lands within noise of 0.90 could
in principle flip across .NET versions. It can only affect an object's **first**
write (SR-061), and both outcomes are correct storage forms. The measured
margins above are wide: the nearest row to the threshold is `mixed-head.bin` at
0.93, and `video.mp4` at 0.46 vs. a real 0.89.
