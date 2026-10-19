"""Round 3s: fixes from the eight-item 'architecture ready for test cases' check (r3s-readiness-check.md)."""
import os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
F = 'docs/runtime-flows.md'
L = 'docs/requirements/low-level-requirements.toml'


def sub(p, old, new):
    s = open(p, encoding='utf-8').read()
    assert s.count(old) == 1, (p, old[:70], s.count(old))
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))


def add_constrains(llr_id, if_id, after_line):
    s = open(L, encoding='utf-8').read()
    head = f'[design.{llr_id}]\n'
    i = s.index(head)
    j = s.index(after_line, i)
    k = j + len(after_line)
    assert 'constrains' not in s[i:s.index('\n[design.', i + 1) if '\n[design.' in s[i + 1:] else len(s)]
    open(L, 'w', encoding='utf-8', newline='').write(s[:k] + f'constrains = "{if_id}"\n' + s[k:])


# Item 2: the folder record and the link record are constrained by the rows that state what is recorded.
sub(L, '[design.LLR-065]\ntitle = "Empty and attributed folders are recorded"\nsr_refs = ["SR-065", "SR-122"]\n',
       '[design.LLR-065]\ntitle = "Empty and attributed folders are recorded"\nsr_refs = ["SR-065", "SR-122"]\nconstrains = "IF-017"\n')
sub(L, '[design.LLR-110]\ntitle = "A recorded link carries its kind and where it led"\nparent = "LLR-109"\n',
       '[design.LLR-110]\ntitle = "A recorded link carries its kind and where it led"\nparent = "LLR-109"\nconstrains = "IF-018"\n')

# LLR-163: where the dry run's verdicts are reported (today: the run's record, no other output).
sub(L, "Its outcome value follows the refusals it found,",
       "Its per-state verdicts are written to the run's record (IF-009), as a removal's are. Its outcome value follows the refusals it found,")

# Item 5: both state flows gain the mid-work failure ending.
sub(F, "    Staged --> Reclaimed: a successor took the backup, the run stops with 1 (LLR-125, SR-144)\n",
       "    Staged --> Reclaimed: a successor took the backup, the run stops with 1 (LLR-125, SR-144)\n    Staged --> Failed: a host fault mid-work gives 4, a location failure 1, leftovers recognised next run (LLR-043, LLR-162)\n    Failed --> [*]\n")
sub(F, "    Restoring --> Finishing: every file written and verified (LLR-056)\n",
       "    Restoring --> Finishing: every file written and verified (LLR-056)\n    Restoring --> Failed: an I/O or tool failure mid-restore, 4, files written stay verified (LLR-040)\n    Failed --> [*]\n")

# Item 3: steps the flows had given to the wrong component.
sub(F, "    Op->>Cfg: validate every location set before the first runs (LLR-042, LLR-014)\n",
       "    Op->>Cfg: validate every location set before the first runs (LLR-042)\n")
sub(F, "    Guard->>Store: read run state, latest record and its evidence (LLR-035, LLR-118)\n",
       "    Pub->>Store: under the claim, read run state, latest record and its evidence (LLR-035, LLR-118)\n")
sub(F, "    Guard->>Guard: open the location's record in the run folder (LLR-095, S06)\n",
       "    Note over Guard,Pub: the location's record opens in the run folder (LLR-095, S06)\n")
sub(F, "                R->>Guard: test the claim without creating it (LLR-159)\n                Guard-->>R: held or untestable gives retry later 4. Free gives damaged record 3 (LLR-123, LLR-039)\n",
       "                R->>Store: test the claim file without creating it (LLR-159)\n                R->>R: held or untestable gives retry later 4. Free gives damaged record 3 (LLR-123, LLR-039)\n")
sub(F, "        Op->>Guard: test the claim without creating it (LLR-163, LLR-159)\n",
       "        Rem->>Store: test the claim file without creating it, an absent file meaning no holder (LLR-163, LLR-159)\n")

# Item 4: behaviour the flows left out.
sub(F, "    Scan->>Scan: names refused, entries not captured are named (LLR-055, LLR-111)\n",
       "    Scan->>Scan: names refused, entries not captured are named, a briefly unreadable file retried within the location's limit (LLR-055, LLR-111, LLR-067)\n    alt the source suddenly looks empty and is not declared so\n        Scan-->>Op: refused, nothing changed (LLR-036)\n    end\n")
sub(F, "    Scan->>Pub: new-or-changed set and removed set\n",
       "    Scan->>Scan: keep the change-detection record at the source root or its configured location (LLR-115, LLR-114)\n    Scan->>Pub: new-or-changed set and removed set\n")
sub(F, "    loop each new content, once per content key\n",
       "    Pub->>Pub: content lost from the store is stored again, existing content adopted only where present (LLR-053)\n    loop each new content, once per content key\n")
sub(F, "    Pub->>Views: rebuild the views where on (LLR-061, LLR-132)\n",
       "    Pub->>Views: rebuild the views where on, with the media rate where measured (LLR-061, LLR-132, LLR-133, LLR-134)\n    Note over Scan,Pub: the run reads what changed, not the history (LLR-149)\n")
sub(F, "    Op->>Ntf: one message where set up, a send failure changes nothing (LLR-015)\n",
       "    Op->>Ntf: one message where set up, a send failure changes nothing, credentials never written readable (LLR-015, LLR-106)\n")
sub(F, "    Kit->>Kit: tools by name and version, target space with allowances (LLR-139, LLR-023)\n",
       "    Kit->>Kit: tools by name and version, the same verdict whatever the host tools' flavour, target space with allowances (LLR-139, LLR-071, LLR-023)\n")
print('round 3s applied')
