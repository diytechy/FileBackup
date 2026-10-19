"""Round 3r: apply the confirmed findings of r3q-convergence-sol (R3Q-001..004)."""
import os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
F = 'docs/runtime-flows.md'
C = 'docs/requirements/components.toml'
L = 'docs/requirements/low-level-requirements.toml'


def sub(p, old, new):
    s = open(p, encoding='utf-8').read()
    assert s.count(old) == 1, (p, old[:70], s.count(old))
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))


# R3Q-001: flow 2 reclaims in LLR-124's order (R1-R2, R4, R5, R6) and creates staging only once.
sub(F, """    opt leftovers provably dead
        Guard->>Guard: move them aside, complete an interrupted publication (LLR-124)
    end
    Guard->>Guard: staging areas, run folders, owner record, refresh timer (LLR-161, LLR-080, S01 to S06)
""", """    alt leftovers provably dead
        Guard->>Guard: move them aside, the backup root's first (LLR-124, R1 to R2)
        Guard->>Guard: fresh staging areas, run folders, owner record, refresh timer (LLR-124, LLR-080, R4)
        Guard->>Store: complete an interrupted publication through this run's own folder (LLR-118, R5)
        Guard->>Guard: delete the moved folders' recognised entries (LLR-124, R6)
    else no leftovers
        Guard->>Guard: staging areas, run folders, owner record, refresh timer (LLR-161, LLR-080, S01 to S05)
    end
    Guard->>Guard: open the location's record in the run folder (LLR-095, S06)
""")

# R3Q-002: flow 9 no longer opens the location record before the action holds the backup.
sub(F, "        Op->>Rec: open the location's record once admitted (LLR-095)\n",
       "        Note over Op,Rec: the location's record opens inside the action, once it holds the backup and has passed admission (LLR-095, S06 in flow 2)\n")

# R3Q-003: an absent claim file is no holder; only an existing held file or a failed test refuses.
sub(L, "a claim found held, or a test that fails, is reported for every named saved state as the removal reports a claim it cannot take (LLR-092).",
       "an absent claim file means no holder, since only an operation taking the claim creates it (IF-032); a claim file found held, or a test that fails on an existing file or an unreachable location, is reported for every named saved state as the removal reports a claim it cannot take (LLR-092).")
sub(L, 'dimensions = "verdict=set{would-remove,refused-2,refused-3,refused-4}; states_named=range[1..3]; outstanding_removal=bool; writer_running=bool; route=set{direct,container}; @pairwise"',
       'dimensions = "verdict=set{would-remove,refused-2,refused-3,refused-4}; states_named=range[1..3]; outstanding_removal=bool; claim_file=set{absent,free,held,test-fails}; route=set{direct,container}; @pairwise"')

# R3Q-004: the component notes follow the IF-010 / IF-047 split.
sub(C, "Its interfaces carry the rows that state the request, the outcome value and the findings document; the report's and the check's own findings rows sit with their components, unplaced.",
       "Its interfaces carry the rows that state the request and the outcome value; it returns, unchanged, the documents the check (IF-010) and the saved-state report (IF-047) produce, whose rows are placed with those components.")
sub(C, "It owns the content-location index; its refusal, confinement, interruption and report rows state behaviour across the outcome value, the request, the store layout and the findings document, owned elsewhere, so they show as unplaced.",
       "It owns the content-location index and the saved-state report (IF-047), where its report row is placed; its refusal, confinement and interruption rows state behaviour across the outcome value, the request and the store layout, owned elsewhere, so they show as unplaced.")
print('round 3r applied')
