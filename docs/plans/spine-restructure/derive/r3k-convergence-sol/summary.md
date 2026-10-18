Convergence review: LLR-162, LLR-118, LLR-123, LLR-124, SR-082, SR-106.

Counts: BLOCKER 2; MAJOR 1; MINOR 0. Total: 3.

- R3K-001 — BLOCKER — LLR-162 / LLR-118: supported version-2 evidence bypasses the metadata-digest upgrade, allowing an interrupted backup to restore old files with new folder metadata as complete.
- R3K-002 — MAJOR — LLR-162 / LLR-124: early-failure cleanup can leave an unlisted prepared-folder shape that LLR-088 classifies as content, permanently refusing harmless leftovers.
- R3K-003 — BLOCKER — LLR-118 / SR-082: unidentified latest-state metadata damage is both replaced from the source with continuation and refused with nothing changed.

No additional finding for LLR-123 or SR-106. Review limited to internal/parent/interface consistency and contradictions involving the six scoped rows; earlier reviews and FileBackup planning documents were not read.
