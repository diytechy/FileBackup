"""Round 3t, second part: what the root N2 chart showed (the run record had no internal producers)."""
import os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
I = 'docs/requirements/interfaces.toml'
L = 'docs/requirements/low-level-requirements.toml'
F = 'docs/runtime-flows.md'


def sub(p, old, new):
    s = open(p, encoding='utf-8').read()
    assert s.count(old) == 1, (p, old[:70], s.count(old))
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))


# Every operation writes the run record; notification reads it for the message body.
sub(I, '[interface.IF-009]\ntitle = "Run record"\nowner = "CMP-006"\nconsumers = ["external:EXT-01", "external:EXT-03"]',
       '[interface.IF-009]\ntitle = "Run record"\nowner = "CMP-006"\nconsumers = ["external:EXT-01", "external:EXT-03", "CMP-005"]')
sub(I, "the machine-readable form is IF-010, and a person reads this one.",
       "the machine-readable forms are IF-010 and IF-047, and a person reads this one.")
s = open(I, encoding='utf-8').read()
s = s.rstrip('\n') + '''

[interface.IF-052]
title = "Record entry"
owner = "CMP-006"
requestors = ["CMP-002", "CMP-003", "CMP-004", "CMP-005", "CMP-009", "CMP-011", "CMP-012", "CMP-013", "CMP-014", "CMP-015"]
channel = "in-process call"
data = """Request: one entry, as its level (one of DEBUG, INFO, WARN, ERROR) and one message of a kind the run record lists (IF-009), a refusal carrying its token, what was found and what to do; and whether it belongs to the global record, the location's record, or both.
Answer: none. Writing an entry never changes the operation's outcome."""
rationale = """Every component reports into the one record through one entry form, so the record's grammar and its location rules live in one place. Each component writing the files itself lost because the grammar, the tokens and the rule that no record is created before admission would each be repeated."""
version = "1"
status = "Drafted"
'''
open(I, 'w', encoding='utf-8', newline='').write(s)
sub(L, 'title = "Every refusal states what was found and what to do"\nsr_refs = ["SR-126"]\nconstrains = "IF-009"',
       'title = "Every refusal states what was found and what to do"\nsr_refs = ["SR-126"]\nconstrains = "IF-052"')

# The top-level state flow (item 12 asks for one per scope).
sub(F, "## Runtime flows\n\n### 1. A backup run: the modes of one location\n",
       """## Runtime flows

### 0. A launch: the modes at the top level

```mermaid
stateDiagram-v2
    direction LR
    [*] --> Started: a launch request, directly or from the container (LLR-016, LLR-048)
    Started --> Refused: a bad request, a refused configuration, or a missing tool (LLR-042, LLR-020)
    Started --> Admitted: every location set validated, dependencies resolved once (LLR-042, LLR-164)
    Admitted --> Running: dispatch each configured location in turn (LLR-014)
    Running --> Running: next location, whatever the last one's value (LLR-014)
    Running --> Folded: every location has a value (LLR-014, LLR-043)
    Folded --> Notified: one message where set up, a failed send changes nothing (LLR-015)
    Folded --> [*]: no notification set up
    Notified --> [*]: one value as the exit status (LLR-043)
    Refused --> [*]
```

### 1. A backup run: the modes of one location
""")
print('round 3t part 2 applied')
