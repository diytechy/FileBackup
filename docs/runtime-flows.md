# Runtime flows — FileBackup (authored with the LLRs, before the test-case review)

The authored half of FileBackup's architecture record. Each diagram renders a
key runtime scenario from the design tier in
[requirements/](requirements/) and cites the SR and LLR ids it renders, so a
reviewer can check ordering, concurrency and what blocks on what here first,
then spot-check the rows. The structural half (components, interfaces, which
LLR sits where) is the registries themselves:
[components.toml](requirements/components.toml),
[interfaces.toml](requirements/interfaces.toml) and
[low-level-requirements.toml](requirements/low-level-requirements.toml).

Participants are **components** (`CMP-NNN`), not code modules: the design names
components, and the code is mapped to them later by `Component:` headers. A
flow renders what the rows say; where a row and a flow disagree, the row wins
and the flow is fixed in the same change.

Each scope also carries a **state flow** (the modes a stakeholder could name
and what moves the run between them), as the decomposition method asks. The
per-scope boundary and dependency analysis that goes with these flows is in
[plans/spine-restructure/derive/r3o-decomposition.md](plans/spine-restructure/derive/r3o-decomposition.md).

## Runtime flows

### 1. A backup run: the modes of one location

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Admitted: configuration and tools admitted (LLR-042, LLR-020)
    Admitted --> Planned: walk, change set, space plan, as a reader (LLR-052, LLR-113)
    Planned --> Refused: a volume lacks space or cannot be measured (LLR-052)
    Planned --> Claimed: claim taken (LLR-090, LLR-091)
    Planned --> Busy: claim held elsewhere (LLR-122)
    Claimed --> Refused: leftovers not provably safe, or a record fails its evidence (LLR-017)
    Claimed --> Staged: leftovers reclaimed or none, staging and owner record made (LLR-124, LLR-080)
    Staged --> Published: objects stored, saved state and latest state published (LLR-150, LLR-118)
    Staged --> Unchanged: empty change set, no saved state (LLR-005)
    Published --> Collapsed: run state written, cross-state duplicates collapsed (LLR-028, LLR-026)
    Unchanged --> Collapsed
    Collapsed --> Released: views built, location record published, staging removed, claim released (LLR-061, LLR-091)
    Staged --> Reclaimed: a successor took the backup, the run stops with 1 (LLR-125, SR-144)
    Released --> [*]
    Refused --> [*]
    Busy --> [*]
    Reclaimed --> [*]
```

### 2. A backup run, one location, in order

Renders SR-005, SR-052, SR-059, SR-082, SR-085 and the staging table's steps
S01 to S27 (LLR-162) at the level a reviewer reads them.

```mermaid
sequenceDiagram
    autonumber
    participant Op as Launch and outcome (CMP-002)
    participant Cfg as Configuration (CMP-003)
    participant Scan as Source scan and change detection (CMP-009)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Pub as Content storage and publication (CMP-011)
    participant Store as Store format (CMP-016)
    participant Views as Views (CMP-015)
    Op->>Cfg: validate every location set before the first runs (LLR-042, LLR-014)
    Note over Op,Cfg: no record is created or truncated before admission (LLR-095)
    Op->>Scan: walk the source read-only, every entry, links classified (LLR-001, LLR-109, LLR-112)
    Scan->>Scan: names refused, entries not captured are named (LLR-055, LLR-111)
    Scan->>Scan: compare size and time, re-read when due (LLR-113, LLR-011)
    Scan->>Pub: new-or-changed set and removed set
    Pub->>Pub: space plan as a reader, before anything is created (LLR-052, LLR-135)
    alt a volume lacks space or cannot be measured
        Pub-->>Op: refused, 2, nothing created
    end
    Op->>Guard: take the claim (LLR-090, LLR-091)
    alt claim held by another operation
        Guard-->>Op: refused busy, 4, touching nothing (LLR-122)
    end
    Guard->>Store: read run state, latest record and its evidence (LLR-035, LLR-118)
    Guard->>Guard: classify leftovers from the disk alone (LLR-017, LLR-088)
    opt leftovers provably dead
        Guard->>Guard: move them aside, complete an interrupted publication (LLR-124)
    end
    Guard->>Guard: staging areas, run folders, owner record, refresh timer (LLR-161, LLR-080, S01 to S06)
    Pub->>Pub: plan again under the claim, binding (LLR-052)
    loop each new content, once per content key
        Pub->>Store: write temporary, verify, rename out (LLR-003, LLR-058, LLR-086, LLR-117, S07 to S08)
    end
    opt change set not empty
        Pub->>Store: prepare the saved state in the run folder, publish it (LLR-005, LLR-150, S09 to S10)
    end
    Pub->>Store: place the latest kit, then folder, link and record temporaries, evidence last (LLR-007, LLR-087, LLR-118, S11 to S17)
    loop each superseded or removed content
        Pub->>Store: rename into the saved state on one volume, verified copy then delete on two (LLR-059, LLR-150, S18 to S20)
    end
    Pub->>Store: run-state record through the run folder (LLR-028, S21)
    Pub->>Store: collapse duplicates across states (LLR-026, S22 to S23)
    Pub->>Views: rebuild the views where on (LLR-061, LLR-132)
    Guard->>Guard: publish location record, empty staging, delete owner record (S24 to S27)
    Guard->>Guard: release the claim on every path (LLR-091)
    Op->>Op: fold this location into the run's value (LLR-014, LLR-043)
```

### 3. Readers beside a writer (concurrent)

A check, the saved-state report and a restore take no claim and still
complete while a backup, a removal, a repair or a kit refresh holds the
backup. Renders SR-106, SR-085 and SR-086.

```mermaid
sequenceDiagram
    autonumber
    participant W as A changing operation (CMP-011, CMP-013 or CMP-014)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Store as Store format (CMP-016)
    participant R as A reader (CMP-014 check, CMP-013 report, or CMP-017 restore)
    participant W2 as A second changing operation
    W->>Guard: take the claim (LLR-090)
    W2->>Guard: take the claim
    Guard-->>W2: held, refused busy 4, touching nothing (LLR-122)
    par the writer publishes
        W->>Store: rename the new record out (S16)
        W->>Store: rename the evidence out (S17)
    and a reader reads at the same moment
        R->>Store: read the record and its evidence, take no claim (LLR-123)
        alt record and evidence disagree
            loop every 2 s for up to 60 s
                R->>Store: read again
            end
            alt they come to agree
                R->>R: read normally, normal outcome
            else still disagree
                R->>Guard: test the claim without creating it (LLR-159)
                Guard-->>R: held or untestable gives retry later 4. Free gives damaged record 3 (LLR-123, LLR-039)
            end
        end
    end
    Note over R,Store: a kit of two revisions during a kit refresh is waited out the same way (LLR-159)
    Note over R,Store: a vanished object or folder is found again by content key (LLR-123, LLR-050)
    W->>Guard: release the claim
```

### 4. A stale run reclaimed, and the former owner resuming (concurrent)

Only possible where the second run cannot see the first run's claim: two
hosts or containers on one backup, which is unsupported (DA-03), or a network
share that dropped a sleeping host's claim. Renders SR-075, SR-144 and the
reclaim steps R1 to R6 (LLR-162).

```mermaid
sequenceDiagram
    autonumber
    participant A as Run A, the former owner (CMP-007)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Store as Store and staging (CMP-016)
    participant B as Run B, the successor (CMP-007)
    A->>Store: staging, run folders, owner record (LLR-080, LLR-161)
    Note over A: A freezes. Its owner record stops being refreshed.
    B->>Guard: take the claim, A's claim not visible (DA-03)
    B->>Store: owner record older than the stale time, unchanged at a second sample (LLR-080)
    B->>Store: move A's staging areas aside, backup root first (LLR-124, R1 to R2)
    B->>Store: fresh staging and B's own owner record (R4)
    B->>Store: complete A's interrupted publication, if one is identified (LLR-118, R5)
    B->>Store: delete A's recognised entries, keep A's location record (R6)
    B->>Store: B's own backup, published (flow 2)
    Note over A: A wakes
    A->>Store: finish the one step it had in flight
    Note over A,Store: a rename through A's run folder fails by itself, because the folder was moved (LLR-125)
    Note over A,Store: one exception, an earlier-content rename on one volume can land, leaving one object misplaced, found by content key (LLR-125, LLR-150)
    A->>Store: re-read the owner record before the next step
    Store-->>A: another run's identity
    A->>A: stop, publish nothing, part failed 1, work reclaimed (LLR-125, SR-144)
```

### 5. A restore: the modes

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Launched: double-click or command line (LLR-074, LLR-073)
    Launched --> Admitting: request and target known (LLR-157, LLR-158)
    Admitting --> Refused: any whole-restore check fails, nothing written (LLR-136)
    Admitting --> Waiting: kit or record not settled (LLR-159, LLR-123)
    Waiting --> Admitting: settled within 60 s
    Waiting --> Refused: still unsettled, 4 or 3 by the claim test (LLR-159, LLR-039)
    Admitting --> Restoring: every check passed
    Restoring --> Finishing: every file written and verified (LLR-056)
    Finishing --> Reported: times, folders, attributes, links applied (LLR-066, LLR-143, LLR-144)
    Reported --> [*]: one value, report kept on screen when started by hand (LLR-040, LLR-074)
    Refused --> [*]
```

### 6. A restore, in order

Both routes (the language runtime and the shell) follow the same flow; parity
between them is a test question. Renders SR-145, SR-039, SR-010, SR-056 and
SR-040.

```mermaid
sequenceDiagram
    autonumber
    actor U as Restorer
    participant Kit as Restore kit (CMP-017)
    participant Ent as Entry restoration (CMP-019)
    participant Out as Outcome and report (CMP-021)
    participant Store as Store format (CMP-016)
    U->>Kit: double-click, or start with arguments (LLR-074)
    Kit->>Kit: launch, and ask for a target only where someone can answer (LLR-073, LLR-156, LLR-157)
    Kit->>Kit: request, target, chosen state (LLR-010, LLR-158)
    Note over Kit: admitting, every check before the target, the report or any file exists (LLR-136)
    Kit->>Kit: target not inside the backup, resolvable, no parent component (LLR-009, LLR-079, LLR-137)
    Kit->>Store: kit of one revision (LLR-159)
    Kit->>Store: record against its evidence, with the wait (LLR-039, LLR-123, LLR-138)
    Kit->>Kit: tools by name and version, target space with allowances (LLR-139, LLR-023)
    alt any check fails
        Kit-->>Out: refused, value by precedence, shown on the console (LLR-136, LLR-040)
    else all pass
        loop each entry of the chosen state's own record
            Ent->>Ent: refuse an entry landing outside the target (LLR-141)
            Ent->>Store: find content at its place or by content key (LLR-050)
            Ent->>Ent: expand or copy, verify length and digest, one recovery (LLR-056, LLR-068)
            Ent->>Out: an entry not restored, with its cause (LLR-029, LLR-142)
        end
        Note over Kit: finishing, after every file is verified
        Kit->>Kit: each file's own time (LLR-066)
        Kit->>Store: folder record, then link record, applied last (LLR-143, LLR-144)
        Out->>U: one value, counts and causes, held on screen when started by hand (LLR-040, LLR-029, LLR-074)
    end
```

### 7. A removal, and its dry run

Renders SR-045, SR-046, SR-101 and SR-153.

```mermaid
sequenceDiagram
    autonumber
    participant Op as Launch and outcome (CMP-002)
    participant Rem as Removal and report (CMP-013)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Store as Store format (CMP-016)
    alt dry run
        Op->>Guard: test the claim without creating it (LLR-163, LLR-159)
        Rem->>Store: the removal's own plan and refusals, as a reader (LLR-163, LLR-046, LLR-047)
        Rem-->>Op: per state, would remove with figures, or refused with value and reason. Nothing written.
    else removal
        Op->>Guard: take the claim for the whole batch (LLR-092)
        loop each named saved state
            Rem->>Store: plan, collect every refusal before changing anything (LLR-046, LLR-126)
            alt any refusal
                Rem-->>Op: refused, store byte-identical
            else safe
                Rem->>Store: re-home content only this state holds, verified (LLR-045)
                Rem->>Store: publish each touched destination record (LLR-087)
                Rem->>Store: prove every remaining entry resolves without the state (LLR-127)
                Rem->>Store: commit, rename the state out of the saved-state naming (LLR-127)
                Rem->>Store: delete it
            end
        end
        Op->>Guard: release the claim
    end
```

### 8. A check, a repair and a kit refresh

Renders SR-049, SR-109, SR-110 and SR-117.

```mermaid
sequenceDiagram
    autonumber
    participant Op as Launch and outcome (CMP-002)
    participant Chk as Check, repair and kit refresh (CMP-014)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Store as Store format (CMP-016)
    alt plain or deep check
        Chk->>Store: walk every state through the content-location index, no claim (LLR-049, LLR-062, LLR-123)
        Chk->>Store: opening bytes per object, and with -Deep every object's digest once (LLR-049)
        Chk-->>Op: one findings document, value by precedence (LLR-096, LLR-054)
    else repair
        Op->>Guard: take the claim (LLR-094)
        Chk->>Store: correct only the three certain classes, one item at a time (LLR-129, LLR-130)
        Op->>Guard: release the claim
    else kit refresh
        Op->>Guard: take the claim (LLR-094)
        Chk->>Store: record each state's original kit revision once (LLR-131)
        Chk->>Store: restorers first, then every other kit file, each whole (LLR-130)
        Note over Chk,Store: a restore meeting a kit of two revisions waits, flow 3 (LLR-159)
        Op->>Guard: release the claim
    end
```

### 9. One launch across locations, directly or in the container

Renders SR-014, SR-016, SR-048 and SR-015.

```mermaid
sequenceDiagram
    autonumber
    actor Host as Host scheduler or owner
    participant Ctr as Container (CMP-023)
    participant Op as Launch and outcome (CMP-002)
    participant Prov as Provisioning (CMP-004)
    participant Rec as Run record (CMP-006)
    participant Ntf as Notification (CMP-005)
    alt in the container
        Host->>Ctr: action word and environment (LLR-048)
        Ctr->>Op: the same launch request a direct start makes (LLR-048)
    else direct
        Host->>Op: launch request (LLR-016)
    end
    Op->>Prov: runtime and every needed tool, before any location (LLR-020, LLR-105, LLR-037)
    loop each configured location, one failure never stops the next
        Op->>Rec: open the location's record once admitted (LLR-095)
        Op->>Op: run the action for that location (flows 2, 7, 8)
        Rec->>Rec: changes, failures, counts, progress at least every 2 minutes (LLR-107, LLR-108, LLR-097)
    end
    Op->>Op: fold the locations' values into one (LLR-014, LLR-043)
    Op->>Ntf: one message where set up, a send failure changes nothing (LLR-015)
    Op-->>Host: the value as exit status (LLR-043, LLR-048)
```

_Update a flow in the same change that alters its LLRs: a stale flow is a
design error._
