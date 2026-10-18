# Round 1 alignment: the frame and the need tier

Two independent derivations from `derive-brief-r1-needs.md`: GPT-6 Astra
(medium, via Codex) in `r1-astra/`, and Claude Opus (medium) in `r1-opus/`.
Neither saw the other. The coordinator aligned them and built the tier now in
`docs/requirements/stakeholder-needs.toml`, `external.toml` and
`assumptions.toml`. Every row is Drafted.

## Size

| | Astra | Opus | Adopted |
|---|---|---|---|
| Needs | 47 (28 kept, 19 new) | 48 (30 kept, 18 new) | 48 |
| Entities | 19 | 14 | 16 |
| Crossings | 24 | 19 | 21 |
| Assumptions | 20 | 17 | 20 |

## Needs: matched, and where they differ

The two sets match on about 44 outcomes by meaning, with nearly the same
legacy ids kept. Both found the same missing needs:

- a source left untouched;
- a vanished source never read as deleting everything;
- concurrent operations on one store;
- store upgrade and version compatibility;
- restore never harming the store or writing outside its target;
- scale;
- observability;
- the reclaim forecast before removal;
- repair of unambiguous problems;
- compression-policy changes never harming saved states;
- partial-failure capture;
- partial-restore salvage;
- credentials;
- the media-space view.

**Opus is the base.** Its needs carry each load-bearing clause in `need` or
`acceptance` rather than in `why`, and its acceptance cells state testable
conditions. It also has the mapping of every legacy need with a reason.

**Only in Opus, adopted:**
- **SN-034**: no later operation ever alters or loses stored content a saved
  state still depends on. This is the vision's own promise. Astra spread it
  across other needs and gave it no home of its own.
- **SN-054**: third-party components ship under terms that allow it, with
  their notices. This is the LEGAL item the Owner said must not be missed.
  Astra only tagged needs `redistribution`.
- **SN-050**: a documented, versioned configuration contract for backup hosts,
  split out of the legacy configuration need.
- **SN-004 and SN-006 kept apart:** keeping dated history, and restoring a
  chosen state. Astra merged them into one need.

**Only in Astra, not adopted, and why:**
- **Restore fidelity as three needs** (file times, empty folders, folder
  attributes). Opus's SN-036 is one outcome, "the restored tree comes back the
  way it was", whose acceptance names all three facets. The SR tier will split
  them, where each is a separate obligation.
- **Running out of space as two needs** (backup, restore). Opus's SN-019 is one
  outcome for three stakeholders, with both cases in acceptance.
- **Applying restore-kit improvements to existing backups.** This is the
  second half of Opus's SN-041.

**Coordinator edits to the base:**
- SN-029, SN-041 and SN-046 used "he"/"him" for the owner; they now use
  neutral wording.
- SN-038's "unless the owner has said that this source may become empty" was
  checked against the code: the legacy empty-source requirement carries a
  per-set opt-in, so it stays.

## Frame

**Opus is the base:** fewer, more testable crossings drawn where an
observable happens. **Adopted from Astra:**
- **EXT-15 / B-20**, the working-state and log locations: the per-source
  change-detection state, the logs and the browse view live outside the store,
  and losing them must never cost stored content.
- **EXT-16 / B-21 and DA-20**, the host's credential protection, behind SN-049.
- **DA-18:** hashing and archive implementations on any host compute the
  documented algorithms. Without this, cross-host restore rests on an unstated
  premise.
- **DA-19:** a handed-over backup folder travels whole. A restorer handed one
  state's folder alone cannot restore shared content.

Astra's finer split of the tools into one entity each (runtime, hashing
library, archive tool, media tool, POSIX toolchain) is kept as Opus's two
bundled entities, "backup runtime and tools" and "restore tools". Crossings may
legitimately carry a bundle; the design tier names each interface.

## For the Owner, before the tier is approved

These needs state obligations the code does not fully meet today. They are
legitimate needs (each serves the vision), but approving them commits the work:

- **SN-044**: progress visible during a long run at least every few minutes.
  The run-observability review found no such requirement.
- **SN-043**: documented time and memory budgets at a documented scale. No
  performance budget exists yet.
- **SN-054**: licence notices travel with every shipped third-party component.
  Unchecked today.
- **SN-049**: notification credentials never readable in plain form from the
  configuration, the backup or a run's record.
