# Owner correction of the reference storage medium

Date: 2026-11-06 (America/Chicago).

The owner clarified the deployed storage:

> The true drives are platter drives, so D: is a good candidate, we perhaps need to update other docs if they are pointing to an SSD.

This scoped amendment changes SR-064's reference storage from local SSD to
local rotational hard-disk (platter) storage. Four cores, 2 GB available memory,
100 MiB/s sequential throughput, the scale envelope and the eight-hour budgets
remain unchanged. SR-112 and SR-113 inherit that reference; their memory,
routine-backup and history-growth limits remain unchanged. These are targets
to validate, not claims that the implementation meets them on HDDs.

Only SR-064 is re-attested in the approved system-requirements snapshot. The
[original SR acceptance](../spine-rebaseline-2026-11-05/sr-approval.md) remains
the record for the other requirements. LLR-189 and TC-299 reflect this correction
and remain Drafted; this does not approve design, interfaces or test results.

D: is the candidate test drive: an HGST SATA rotational disk. Record the physical
devices, filesystems and placement of source, store, restore target and scratch
for each timing run, including whether they share a spindle. Sequential transfer
rate alone does not characterize small-file seeks, metadata operations or flush
latency. Existing D: trials are partial evidence; neither they nor SSD or RAM
trials qualify the full HDD reference envelope. No new IOPS target or relaxed
time budget is introduced by this correction.

The [performance record](performance-validation.md) retains accurate storage
labels for earlier measurements. Earlier review discussions about an SSD
reference are historical and are superseded by this amendment. Full HDD
qualification remains open; the available D: capacity does not accommodate a
full 2 TiB corpus, so smaller trials must remain labelled as characterization.
