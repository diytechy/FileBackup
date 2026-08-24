# WP8 — Portable filenames + raw-candidate recovery

Minted by human ruling 2026-08-23 alongside WP7 (status.md). Two small items
batched because the second bumps the kit revision.

## Scope

1. **Portable-name guard (R6/R7 disposition, human-ruled):** at backup time, a
   source filename that is invalid on either platform — any character from the
   Windows-invalid set (`< > : " | ? *`, control chars incl. newline) or a
   backslash in a name component on Linux — is **skipped loudly**: one ERROR
   per file naming the offending character, the set fails (non-zero exit), no
   silent handling. This keeps every stored manifest restorable by BOTH
   restorers on both platforms and retires R6 (7-Zip quote mis-split) and R7
   (bash newline-row parse) at the source.
2. **Raw-candidate recovery without 7-Zip (R10):** during hash recovery, a
   `.7z`-NAMED candidate is first tested as raw bytes (hash of its own
   content — needs no 7-Zip) before the no-7-Zip skip fires, in BOTH
   restorers. A restore that needs no actual decompression then succeeds
   instead of exiting 4 "install 7-Zip". **Kit revision 4 → 5.**

## Registries

SR-055 (portable-name refusal) + LLR-055 + TC; SR-050's family extended for
the raw-first candidate order (TC update on the revision-3 cases); kit
revision notes in AGENTS.md §3 + README.

## Out of scope

Handling (rather than refusing) non-portable names; RFC-4180 newline rows in
the bash parser (retired by the guard for new stores; legacy stores stay
loud-fail — bash-v2 if ever needed).
