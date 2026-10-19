"""Round 3v: apply the confirmed findings of r3u-convergence-sol (R3U-001..009, 011..014).

R3U-010 (assign the restore kit's phase work to its children) is not taken: it
contradicts the Owner's Call 4 (the phases are states of the restore kit). It is
recorded for the Owner in DECOMPOSITION-REVIEW.md and as a model ambiguity in
ARCHITECTURE-FINDINGS.md.
"""
import os
import re

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
I = 'docs/requirements/interfaces.toml'
L = 'docs/requirements/low-level-requirements.toml'
F = 'docs/runtime-flows.md'
G = 'docs/plans/spine-restructure/derive/r3-merged/design-gaps.md'


def read(p):
    return open(p, encoding='utf-8').read()


def write(p, s):
    open(p, 'w', encoding='utf-8', newline='').write(s)


def sub(p, old, new):
    s = read(p)
    assert s.count(old) == 1, (p, old[:70], s.count(old))
    write(p, s.replace(old, new))


def set_block_cell(p, header, key, new_value):
    s = read(p)
    i = s.index(header)
    j = s.find('\n[', i + 1)
    j = len(s) if j < 0 else j
    block = s[i:j]
    m = re.search(r'^' + key + r' = (""".*?"""|"[^"\n]*"|\[[^\]]*\])$', block, re.M | re.S)
    assert m, (header, key)
    write(p, s[:i] + block[:m.start()] + key + ' = ' + new_value + block[m.end():] + s[j:])


# R3U-001, 002, 003: the change set's form is closed and carries what publication needs.
set_block_cell(I, '[interface.IF-049]', 'data', '"""For one location: each walked file with its path, size, modification time and attributes, and one of new (with its digest), changed (with its digest) or unchanged (with its recorded digest and stored-copy reference); each entry of the latest record that no walked file matches, as removed, with its path and recorded digest; each entry not captured, and each name refused, with its cause, kept with its earlier entry where there is one; each folder to record (empty, or carrying an attribute) and each link to record, for the folder record (IF-017) and the link record (IF-018); whether a full re-read was due, when it began and whether it completed; whether the change-detection state was rebuilt, and why; and the location\'s wait budget left (seconds)."""')
sub(L, 'Paths are compared with the forward slash and the backslash taken as the same separator, so a record written with the other separator makes no file new or removed.',
       'Paths are compared with the forward slash and the backslash taken as the same separator, so a record written with the other separator makes no file new or removed. A comparison made before the claim, as a reader, is provisional and serves only the space plan (LLR-052); the change set the run acts on is made under the claim, against the latest record as it then is, after stored copies no longer present are blanked (LLR-053), and carries the re-read\'s result and the wait budget the walk left, so storing charges the same budget (LLR-067).')

# R3U-004: the recovery folder travels to the report.
set_block_cell(I, '[interface.IF-050]', 'data', '"""For each entry of the chosen state\'s record, one of: restored and verified, with, where one recovery from another copy was needed, the folder that copy came from; or not restored, with its cause and its class, one of content that could not be produced, two names colliding on the target, an entry escaping the target, or a host fault."""')
set_block_cell(I, '[interface.IF-050]', 'rationale', '"""The outcome classification must not repeat the content search or the verification; these results are the narrow value between the two. Classifying inside entry restoration lost because the precedence over whole-restore faults (IF-054) and per-entry faults would then be split across two places."""')

# R3U-005, 006: the restore kit's own states hand their results to its children.
s = read(I)
s = s.rstrip('\n') + '''

[interface.IF-053]
title = "Admitted restore"
owner = "CMP-017"
consumers = ["CMP-019"]
channel = "in-process call"
data = """Once for each restore, after every whole-restore check has passed: the chosen state's folder and its record of contents (IF-014), the target's resolved physical location, the folders of the pool (the backup root and every saved-state folder), and the tools the route admitted (IF-024); then, one at a time, each entry of that record to restore."""
rationale = """Entry restoration must not repeat the admission checks or choose the state itself; the admitted restore is the narrow value between the two. Letting entry restoration read the request lost because the request names a state and roots the admission may have resolved differently."""
version = "1"
status = "Drafted"

[interface.IF-054]
title = "Whole-restore results"
owner = "CMP-017"
consumers = ["CMP-021"]
channel = "in-process call"
data = """Before anything is written: each whole-restore check, passed, or failed with its cause and its class, one of a bad request, a precondition not met, a damaged record, or a kit or record not settled. After every file is written: each folder, folder attribute, link or file time not applied, with its cause."""
rationale = """The restore's one value takes whole-restore faults over per-entry ones; the outcome classification must see both kinds, each in its own form. Folding these into the entry results lost because a refusal before any entry, and a folder not applied after every entry, belong to no entry."""
version = "1"
status = "Drafted"
'''
write(I, s)
sub(L, '[design.LLR-010]\ntitle = "The chosen state\'s own record is the sole authority"\nsr_refs = ["SR-010"]\nconstrains = "IF-020"',
       '[design.LLR-010]\ntitle = "The chosen state\'s own record is the sole authority"\nsr_refs = ["SR-010"]\nconstrains = "IF-053"')
sub(L, '[design.LLR-136]\ntitle = "Every whole-restore check is made before anything is written"\nsr_refs = ["SR-145"]\n',
       '[design.LLR-136]\ntitle = "Every whole-restore check is made before anything is written"\nsr_refs = ["SR-145"]\nconstrains = "IF-054"\n')

# R3U-007: the launch-wide space plan is a request kind of its own.
sub(I, 'Request, once for each configured location: the action, one of a backup,',
       'Request, once for each configured location: the action, one of a plan (for a backup: a reader\'s pass that changes nothing and answers with the location\'s space demand on each volume), a backup,')
sub(I, 'Answer: one outcome value of the shared vocabulary (the set of IF-003); each refusal or failure',
       'Answer: for a plan, the demand on each volume (the volume\'s identity and the bytes needed); otherwise one outcome value of the shared vocabulary (the set of IF-003); each refusal or failure')

# R3U-011, 012, 013: endpoints.
sub(I, 'requestors = ["external:EXT-01", "external:EXT-03", "CMP-002"]',
       'requestors = ["external:EXT-01", "external:EXT-03", "CMP-002", "CMP-004", "CMP-005"]')
sub(I, 'consumers = ["external:EXT-03", "external:EXT-01", "CMP-005"]',
       'consumers = ["external:EXT-03", "external:EXT-01", "CMP-005", "CMP-023"]')
sub(I, '[interface.IF-051]\ntitle = "Resolved dependencies"\nowner = "CMP-004"\nconsumers = ["CMP-002", "CMP-011", "CMP-013", "CMP-014", "CMP-015"]',
       '[interface.IF-051]\ntitle = "Resolved dependencies"\nowner = "CMP-004"\nconsumers = ["CMP-002", "CMP-009", "CMP-011", "CMP-013", "CMP-014", "CMP-015"]')

# R3U-014: behaviour out of the form (no new obligation is invented).
sub(I, 'Answer: none. Writing an entry never changes the operation\'s outcome."""',
       'Answer: none."""')

# The reviewer's code note: some paths append to records directly, outside the one entry form.
sub(G, '\n96 gaps.', '\n| M97 | SR-124, SR-126 | LLR-097, IF-052 | review (R3U code note) | Several paths append to the run records directly rather than through the shared logger. | Every entry is written through the one record-entry form (IF-052). |\n\n97 gaps.')

# R3U-007, 008: flow 0 and flow 9 put admission first and plan every location before any runs.
s = read(F)
a = s.index('### 0. A launch: the modes at the top level')
b = s.index('### 1. A backup run: the modes of one location')
s = s[:a] + '''### 0. A launch: the modes at the top level

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Started: a launch request, directly or from the container (LLR-016, LLR-048)
    Started --> Refused: a bad request or a refused configuration, before anything is loaded (LLR-042)
    Started --> Admitted: every location set validated (LLR-042)
    Admitted --> Refused: a missing runtime or tool (LLR-020)
    Admitted --> Provisioned: dependencies resolved once for the launch (LLR-164)
    Provisioned --> Planned: for a backup, every location planned as a reader and demand summed per volume (LLR-052)
    Provisioned --> Running: any other action (LLR-014)
    Planned --> Running: locations on a short or unmeasurable volume refused, the rest dispatched (LLR-052, LLR-014)
    Running --> Running: next location, whatever the last one's value (LLR-014)
    Running --> Folded: every location has a value (LLR-014, LLR-043)
    Folded --> Notified: one message where set up, a failed send changes nothing (LLR-015)
    Folded --> [*]: no notification set up
    Notified --> [*]: one value as the exit status (LLR-043)
    Refused --> [*]
```

''' + s[b:]
write(F, s)

s = read(F)
a = s.index('```mermaid', s.index('### 2. A backup run, one location, in order'))
b = s.index('```', s.index('sequenceDiagram', a) + 1) + 3
s = s[:a] + '''```mermaid
sequenceDiagram
    autonumber
    participant Op as Launch and outcome (CMP-002)
    participant Scan as Source scan and change detection (CMP-009)
    participant Guard as Exclusive-use guard (CMP-012)
    participant Pub as Content storage and publication (CMP-011)
    participant Store as Store format (CMP-016)
    participant Views as Views (CMP-015)
    Note over Op,Pub: the location arrives admitted and already planned with every other location, as a reader (flow 9)
    Op->>Pub: run the backup for this location (IF-048)
    Pub->>Guard: take the claim (LLR-090, LLR-091)
    alt claim held by another operation
        Guard-->>Pub: held, refused busy 4, touching nothing (LLR-122)
        Pub-->>Op: the location's value and reason (IF-048)
    end
    Pub->>Store: under the claim, read run state, latest record and its evidence (LLR-035, LLR-118)
    Guard->>Guard: classify leftovers from the disk alone (LLR-017, LLR-088)
    alt leftovers provably dead
        Guard->>Guard: move them aside, the backup root's first (LLR-124, R1 to R2)
        Guard->>Guard: fresh staging areas, run folders, owner record, refresh timer (LLR-124, LLR-080, R4)
        Guard->>Store: complete an interrupted publication through this run's own folder (LLR-118, R5)
        Guard->>Guard: delete the moved folders' recognised entries (LLR-124, R6)
    else no leftovers
        Guard->>Guard: staging areas, run folders, owner record, refresh timer (LLR-161, LLR-080, S01 to S05)
    end
    Note over Guard,Pub: the location's record opens in the run folder (LLR-095, S06)
    Pub->>Pub: blank the references to stored copies no longer present (LLR-053)
    Pub->>Scan: the change set against the latest record as it now is (IF-049)
    Scan->>Scan: walk the source read-only, every entry, links classified (LLR-001, LLR-109, LLR-112)
    Scan->>Scan: names refused, entries not captured are named, a briefly unreadable file retried within the location's wait budget (LLR-055, LLR-111, LLR-067)
    alt the source suddenly looks empty and is not declared so
        Scan-->>Pub: refused, nothing changed (LLR-036)
    end
    Scan->>Scan: compare size and time, re-read when due (LLR-113, LLR-011)
    Scan->>Scan: keep the change-detection record at the source root or its configured location (LLR-115, LLR-114)
    Scan-->>Pub: the binding change set, the re-read's result, the wait budget left (IF-049)
    Pub->>Pub: plan again under the claim, binding (LLR-052)
    Pub->>Pub: content lost from the store is stored again, existing content adopted only where present (LLR-053)
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
    Pub->>Store: run-state record through the run folder, with the re-read's start where it completed (LLR-028, S21)
    Pub->>Store: collapse duplicates across states (LLR-026, S22 to S23)
    Op->>Views: rebuild the views where on, with the media rate where measured (LLR-061, LLR-132, LLR-133, LLR-134)
    Note over Scan,Pub: the run reads what changed, not the history (LLR-149)
    Guard->>Guard: publish location record, empty staging, delete owner record (S24 to S27)
    Guard->>Guard: release the claim on every path (LLR-091)
    Op->>Op: fold this location into the run's value (LLR-014, LLR-043)
```''' + s[b:]
write(F, s)

s = read(F)
a = s.index('```mermaid', s.index('### 9. One launch across locations'))
b = s.index('```', s.index('sequenceDiagram', a) + 1) + 3
s = s[:a] + '''```mermaid
sequenceDiagram
    autonumber
    actor Host as Host scheduler or owner
    participant Ctr as Container (CMP-023)
    participant Op as Launch and outcome (CMP-002)
    participant Cfg as Configuration (CMP-003)
    participant Prov as Provisioning (CMP-004)
    participant Rec as Run record (CMP-006)
    participant Ntf as Notification (CMP-005)
    alt in the container
        Host->>Ctr: action word and environment (LLR-048)
        Ctr->>Op: the same launch request a direct start makes (IF-002)
    else direct
        Host->>Op: launch request (LLR-016)
    end
    Op->>Cfg: validate every location set and the global record's location, before anything is loaded (IF-004)
    Note over Op,Cfg: every location set validated, a refusal touching nothing (LLR-042, LLR-155, LLR-095)
    Op->>Prov: runtime and every needed tool, with the configured tool settings (IF-051)
    Prov->>Prov: check the runtime, locate the tools, load the hashing component (LLR-020, LLR-105, LLR-037)
    Prov-->>Op: the dependencies, resolved once for the launch (LLR-164)
    opt a backup
        loop each configured location, as a reader, changing nothing
            Op->>Op: plan, walk and compare as a reader, demand per volume (IF-048)
        end
        Op->>Op: sum the demand per volume, refuse the locations on a short or unmeasurable volume (LLR-052, LLR-135)
    end
    loop each location not refused, one failure never stops the next
        Note over Op,Rec: the location's record opens inside the action, once it holds the backup (LLR-095, S06 in flow 2)
        Op->>Op: dispatch the action for that location and take its value (LLR-014, flows 2, 7, 8)
        Rec->>Rec: changes, failures, counts, progress at least every 2 minutes (LLR-107, LLR-108, LLR-097)
    end
    Op->>Op: fold the locations' values into one (LLR-014, LLR-043)
    Op->>Ntf: the run's value and record, with the notification settings (IF-003)
    Ntf->>Ntf: one message where set up, a send failure changes nothing, credentials never written readable (LLR-015, LLR-106)
    Op-->>Host: the value as exit status (LLR-043, LLR-048)
```''' + s[b:]
write(F, s)
print('round 3v applied')
