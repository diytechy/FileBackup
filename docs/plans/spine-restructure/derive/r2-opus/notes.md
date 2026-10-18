# r2-opus derivation notes

## Per need

- SN-001: SR-101, SR-102, SR-103, SR-104, SR-133
- SN-052: SR-105, SR-106, SR-107
- SN-032: SR-108, SR-109, SR-177
- SN-037: SR-110, SR-111, SR-180
- SN-038: SR-112
- SN-009: SR-113, SR-114
- SN-002: SR-115
- SN-003: SR-116, SR-117 (byte-exact restore either way is carried by SR-168)
- SN-051: SR-118, SR-119, SR-120
- SN-004: SR-121, SR-122
- SN-034: SR-123, SR-133, SR-180 ("no recorded content unaccounted for" is carried by the check, SR-142)
- SN-029: SR-124, SR-125, SR-126
- SN-046: SR-127, SR-128, SR-129
- SN-021: SR-122, SR-130
- SN-007: SR-131, SR-132
- SN-013: SR-134, SR-135, SR-136
- SN-039: SR-137, SR-138, SR-139
- SN-031: SR-140, SR-141
- SN-030: SR-128, SR-129, SR-142
- SN-047: SR-143, SR-144
- SN-048: SR-145, SR-146 ("never wrong bytes under a name" is also delivered by SR-168)
- SN-019: SR-147, SR-148
- SN-043: SR-149, SR-150, SR-151
- SN-040: SR-152, SR-153, SR-185
- SN-041: SR-144, SR-154, SR-155, SR-156, SR-157
- SN-023: SR-158, SR-159
- SN-005: SR-160, SR-161
- SN-006: SR-162
- SN-022: SR-161, SR-163, SR-164, SR-165
- SN-035: SR-166, SR-167
- SN-033: SR-168, SR-169
- SN-053: SR-169, SR-170, SR-177
- SN-025: SR-171
- SN-042: SR-172, SR-173
- SN-036: SR-174, SR-175, SR-176
- SN-026: SR-178
- SN-008: SR-179
- SN-011: SR-167, SR-181
- SN-045: SR-129, SR-182
- SN-044: SR-104, SR-183, SR-184, SR-185
- SN-010: SR-186, SR-187
- SN-049: SR-188, SR-189
- SN-024: SR-111, SR-190, SR-191
- SN-054: SR-192
- SN-012: SR-193, SR-194
- SN-050: SR-195, SR-196, SR-197
- SN-027: SR-180, SR-185, SR-198
- SN-015: SR-120, SR-185, SR-194, SR-199, SR-200

No need is left without an SR.

## Derived rows (obligation through a hat, argued in rationale)

- SR-133, INTEGRITY-RECOVERABILITY: a missing, torn or stale change-detection state must not cost a change or stored content. It traces to SN-001 and SN-034, but neither names that state.
- SR-144, INTEGRITY-RECOVERABILITY: an interrupted repair or kit refresh leaves every state restorable. The needs (SN-047, SN-041) promise restorability after these operations, not during them.
- SR-177, CROSS-PLATFORM: names that collide on a case-insensitive or normalising restore target are named and never merged (SN-032, SN-053; DA-08's obstacle).

The other 37 rows that carry `hat_refs` record attribution by the listens_for test. Their obligations are in the need text, so they are not derived.

Two rows are off the single-crossing rule on purpose, and their rationale says so: SR-149 to SR-151 state performance as a whole-operation property (launch to outcome).

## Possible missing needs

- Dry run of a removal (`-WhatIf` with Prune): the manual offers it, but no need asks for a preview that changes nothing. SN-046 covers the reclaim report only. Not written.
- A failed browse-view refresh not changing the run's outcome: the manual says this, but SN-008 does not ask for it, and no hat clearly reaches it (SN-008 carries no tags). Not written.
- `-RequireWitness` / `--require-witness` (refuse a state that has no integrity record): no need asks a restorer to be able to opt into strictness. SR-156 restores such states and reports the check as not made. Not written.
- An action flag that does not apply to the action (`-Action Backup -WhatIf` refused with 2): close to SN-027 ("never guesses"), but SN-027 is about the configuration, not launch flags. Possible missing need, or a widening of SN-027.
- The compression level knob (an environment variable): no need asks for it. Not written.
- Source links and junctions are not followed. SN-001 says "the whole of each source tree", so content behind a junction would be a silent omission unless it is named in the run's record. A need, or an amendment to SN-001, should rule on links. Not written.
- File attributes (hidden, system or read-only on files) are not restored. SN-036 asks only for folder attributes and file times. If the owner expects file attributes back, that is a missing need.

## Questions I could not settle without the forbidden inputs

1. SN-037 against the default change-detection-state location. The manual says this state lives in the source root by default. That writes into the source, which SN-037 forbids, and makes SR-111 (read-only source) fail. I wrote SR-110 and SR-111 as the need demands. Does the legacy default survive, and if so, under which need?
2. SN-003 against CompressProbe `off` and `excluded-extensions`, and against the small-file floor. SN-003 says "whatever the file's name". The manual's `off` mode, `excluded-extensions` mode and the below-floor tail let the name decide. SR-116 follows the need. Is the need too strong, or are those modes out of line with it?
3. The minimum saving that counts as "measurably saves space" (the manual implies 10% over samples). SR-116 says "the documented minimum". What value, and is sampling acceptable as "measuring"?
4. The outcome values for backup, removal and check (SR-182). SN-045 wants four distinct classes. The manual shows 0, 1 and 2 for a backup, and 2 for a lock-held refusal under Verify, so "configuration refused" and "busy or not ready" may share a value. Which values are the contract?
5. The restore's missing-tool class (SR-164, SR-178). The manual puts a missing required tool under 2 (precondition) and an unavailable archive tool for an archive-shaped item under 4 (host). SN-026 lists "host or tool problem" as one class. I left SR-164 without a value.
6. Budgets for SN-043 (SR-149 to SR-151): the documented scale, host class, time budgets, memory bounds and the margin for history independence are not in my inputs.
7. The progress interval for SR-184 ("every few minutes"). What is the documented value?
8. The bounded extra wait for SR-106, and the retry window for SR-105: what are their values?
9. SN-012 against SN-011 on component install. The manual says the first run "prompts unless already present". An unattended first run must not prompt (SN-011). SR-194 is written to obtain the component or refuse, never to prompt.
10. SN-050 / SR-197 against the unversioned legacy configuration form. The manual exempts one configuration form from ConfigVersion and from the closed schema. SN-050's "each configuration states which version" does not exempt it. Is the legacy form retired, or does it need its own ruling?
11. SN-049 / SR-189 against the legacy form that carries a protected credential object. That form holds credentials in protected, not readable, form, so I believe it passes SR-188 and SR-189 under DA-20, but the boundary (B-21) suggests the credentials never enter the configuration at all.
12. SN-051's "list backed-up files by the space they take": which feature or setting turns the space view on? The manual names a media column that depends on the optional tool, but no setting.
13. SN-030 "altered" content: the manual says detecting it needs the deep option (and the archive tool). SR-142 asks a check to report alteration. Is a check without the deep option compliant with SN-030?
