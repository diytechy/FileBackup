"""Round 3t: the root-scope decomposition pass (unattended, session 2026-10-18 e).

Names the four values that passed between components with no interface row,
completes two consumer lists, and fixes the flows' performers.
Decisions are recorded in derive/r3t-root-decomposition.md and DECOMPOSITION-REVIEW.md.
"""
import os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
I = 'docs/requirements/interfaces.toml'
L = 'docs/requirements/low-level-requirements.toml'
F = 'docs/runtime-flows.md'


def read(p):
    return open(p, encoding='utf-8').read()


def write(p, s):
    open(p, 'w', encoding='utf-8', newline='').write(s)


def sub(p, old, new, count=1):
    s = read(p)
    assert s.count(old) == count, (p, old[:70], s.count(old))
    write(p, s.replace(old, new))


# ---- four internal interfaces ------------------------------------------------
NEW_IFS = '''
[interface.IF-048]
title = "Location operation request and result"
owner = "CMP-002"
consumers = ["CMP-009", "CMP-011", "CMP-013", "CMP-014", "CMP-015"]
channel = "in-process call"
data = """Request, once for each configured location: the action, one of a backup, a removal (the saved states named, and whether it is a dry run), the saved-state report, a check (whether to repair, to refresh the kits, to read every stored object, or to check the latest state only) or a view rebuild; the location set as admitted (IF-004); the dependencies resolved at launch (IF-051); whether the launch has an interactive session; and the record to write to (IF-009).
Answer: one outcome value of the shared vocabulary (the set of IF-003); each refusal or failure with its class, what was found and what to do; and, for a check and for the saved-state report, the findings document (IF-010, IF-047)."""
rationale = """Every operation reports to the launch in one form, so the fold into one value and the never-prompt rule are decided once. Letting each operation return its own shape lost because the launch would need to know each one to fold them."""
version = "1"
status = "Drafted"

[interface.IF-049]
title = "Change set"
owner = "CMP-009"
consumers = ["CMP-011"]
channel = "in-process call"
data = """For one location and one walk: each walked file with its path, size, modification time and attributes, and one of new, changed (with its digest), unchanged (with its recorded digest) or removed; each entry not captured, with its cause, kept with its earlier content; each name refused, with its reason; each folder to record (empty, or carrying an attribute) and each link to record, for the folder record (IF-017) and the link record (IF-018); and whether the change-detection state was rebuilt, and why."""
rationale = """Publication must not repeat the walk or the comparison, and change detection must not know how states are published; the change set is the narrow value between the two decisions. Publication reading the change-detection record itself lost because the comparison rules would then live in two places."""
version = "1"
status = "Drafted"

[interface.IF-050]
title = "Entry results"
owner = "CMP-019"
consumers = ["CMP-021"]
channel = "in-process call"
data = """For each entry of the chosen state's record, one of: restored and verified, with whether one recovery from another copy was needed; or not restored, with its cause and its class, one of content that could not be produced, two names colliding on the target, an entry escaping the target, or a host fault."""
rationale = """The restore's one value and its report are decided from these results alone, the same on every route. Classifying inside entry restoration lost because the precedence over whole-restore faults and per-entry faults would then be split across two places."""
version = "1"
status = "Drafted"

[interface.IF-051]
title = "Resolved dependencies"
owner = "CMP-004"
consumers = ["CMP-002", "CMP-011", "CMP-013", "CMP-014", "CMP-015"]
channel = "in-process call"
data = """Once for each launch: the runtime version and whether it meets the floor; the archive tool's location, or absent; the media-measurement tool's location, or absent, an absent one being a skipped extra; the hashing component, loaded; and the compression effort (IF-007)."""
rationale = """Every location of a launch uses the same tools, found once; resolving them per location lost because one launch could then compress with two different tools, and a missing tool would be reported once per location."""
version = "1"
status = "Drafted"
'''
s = read(I)
write(I, s.rstrip('\n') + '\n' + NEW_IFS)

# ---- consumer lists the flows showed incomplete --------------------------------
sub(I, '[interface.IF-002]\ntitle = "Backup launch request"\nowner = "CMP-002"\nrequestors = ["external:EXT-01", "external:EXT-03"]',
       '[interface.IF-002]\ntitle = "Backup launch request"\nowner = "CMP-002"\nrequestors = ["external:EXT-01", "external:EXT-03", "CMP-023"]')
sub(I, '[interface.IF-003]\ntitle = "Operation outcome value"\nowner = "CMP-002"\nconsumers = ["external:EXT-03", "external:EXT-01"]',
       '[interface.IF-003]\ntitle = "Operation outcome value"\nowner = "CMP-002"\nconsumers = ["external:EXT-03", "external:EXT-01", "CMP-005"]')
sub(I, '[interface.IF-004]\ntitle = "Configuration settings catalogue"\nowner = "CMP-003"\nrequestors = ["external:EXT-01", "external:EXT-03"]',
       '[interface.IF-004]\ntitle = "Configuration settings catalogue"\nowner = "CMP-003"\nrequestors = ["external:EXT-01", "external:EXT-03", "CMP-002"]')  # a row may not carry both consumers and requestors

# ---- LLRs onto the interfaces they describe ------------------------------------
sub(L, '[design.LLR-014]\ntitle = "Configured locations run independently and fold into one value"\nsr_refs = ["SR-014", "SR-095"]\nconstrains = "IF-003"',
       '[design.LLR-014]\ntitle = "Configured locations run independently and fold into one value"\nsr_refs = ["SR-014", "SR-095"]\nconstrains = "IF-048"')
sub(L, 'title = "The change set comes from size, time and, when re-read, content"\nsr_refs = ["SR-088", "SR-105", "SR-024"]\nconstrains = "IF-029"',
       'title = "The change set comes from size, time and, when re-read, content"\nsr_refs = ["SR-088", "SR-105", "SR-024"]\nconstrains = "IF-049"')
sub(L, 'title = "Every written file is verified, with one recovery from another copy"\nsr_refs = ["SR-056", "SR-119"]\nconstrains = "IF-023"',
       'title = "Every written file is verified, with one recovery from another copy"\nsr_refs = ["SR-056", "SR-119"]\nconstrains = "IF-050"')
s = read(L)
write(L, s.rstrip('\n') + '''

[design.LLR-164]
title = "The dependencies are resolved once per launch, and every location uses them"
parent = "LLR-020"
constrains = "IF-051"
detail = """The runtime check, the location of the archive tool and of the media-measurement tool, the loading of the hashing component and the reading of the compression effort are made once for each launch, before any location runs. Every location's operation then uses the tools located and the component loaded at that point, and an optional extra that is absent is recorded as skipped once for the launch, not once for each location."""
dimensions = "archive_tool=set{present,absent}; media_tool=set{present,absent}; locations=range[1..3]; compress=bool; @pairwise"
rationale = """One launch must not compress with two different tools or report one missing tool several times; resolving per location lost for that reason, and because a tool removed during a run would then change the result half way."""
status = "Drafted"
''')

# ---- flows: the component that does the work ------------------------------------
sub(F, "    Op->>Guard: take the claim (LLR-090, LLR-091)\n    alt claim held by another operation\n        Guard-->>Op: refused busy, 4, touching nothing (LLR-122)\n    end\n",
       "    Pub->>Guard: take the claim (LLR-090, LLR-091)\n    alt claim held by another operation\n        Guard-->>Pub: held, refused busy 4, touching nothing (LLR-122)\n        Pub-->>Op: the location's value and reason (LLR-014)\n    end\n")
sub(F, "    Pub->>Views: rebuild the views where on, with the media rate where measured (LLR-061, LLR-132, LLR-133, LLR-134)\n",
       "    Op->>Views: rebuild the views where on, with the media rate where measured (LLR-061, LLR-132, LLR-133, LLR-134)\n")
sub(F, "    Scan->>Scan: keep the change-detection record at the source root or its configured location (LLR-115, LLR-114)\n    Scan->>Pub: new-or-changed set and removed set\n",
       "    Scan->>Scan: keep the change-detection record at the source root or its configured location (LLR-115, LLR-114)\n    Scan->>Pub: the change set (LLR-113)\n")
sub(F, "        Op->>Guard: take the claim for the whole batch (LLR-092)\n",
       "        Rem->>Guard: take the claim for the whole batch (LLR-092)\n")
sub(F, "                Rem->>Store: delete it\n            end\n        end\n        Op->>Guard: release the claim\n",
       "                Rem->>Store: delete it\n            end\n        end\n        Rem->>Guard: release the claim\n")
sub(F, "        Op->>Guard: take the claim (LLR-094)\n        Chk->>Store: correct only the three certain classes, one item at a time (LLR-129, LLR-130)\n        Op->>Guard: release the claim\n",
       "        Chk->>Guard: take the claim (LLR-094)\n        Chk->>Store: correct only the three certain classes, one item at a time (LLR-129, LLR-130)\n        Chk->>Guard: release the claim\n")
sub(F, "        Op->>Guard: take the claim (LLR-094)\n        Chk->>Store: record each state's original kit revision once (LLR-131)\n",
       "        Chk->>Guard: take the claim (LLR-094)\n        Chk->>Store: record each state's original kit revision once (LLR-131)\n")
sub(F, "        Note over Chk,Store: a restore meeting a kit of two revisions waits, flow 3 (LLR-159)\n        Op->>Guard: release the claim\n",
       "        Note over Chk,Store: a restore meeting a kit of two revisions waits, flow 3 (LLR-159)\n        Chk->>Guard: release the claim\n")
sub(F, "    participant Store as Store and staging (CMP-016)\n",
       "    participant Store as Staging and owner record (CMP-012)\n")
sub(F, "    Op->>Prov: runtime and every needed tool, before any location (LLR-020, LLR-105, LLR-037)\n",
       "    Op->>Prov: runtime and every needed tool, before any location (LLR-020, LLR-105, LLR-037)\n    Prov-->>Op: the dependencies, resolved once for the launch (LLR-164)\n")
sub(F, "        Op->>Op: run the action for that location (flows 2, 7, 8)\n",
       "        Op->>Op: dispatch the action for that location and take its value (LLR-014, flows 2, 7, 8)\n")
print('round 3t applied')

# Applied after the first run (see r3t-root-decomposition.md): the guard's reclaim reads and
# republishes records and evidence, so CMP-012 joins IF-014's and IF-015's consumers.
