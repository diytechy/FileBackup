# Owner approval of the external frame

Date: 2026-11-05 (America/Chicago).

After reviewing the boundary guide and external registry, including the
DeepSeek findings and their dispositions, the owner directed:

> I think this and external appear sufficient, you can proceed

This approves the external-frame text at `dac0155`: EXT-01 through EXT-18,
B-01 through B-23, and REL-01 through REL-05 (46 rows). Only their statuses
change in this act. B-24 remains Drafted as an explicitly inactive legacy
reference, excluded from approval pending SR-093/139 reconciliation.

The owner accepted the guide's interpretation of whole-store checks: examine
every remaining state record and report missing or inconsistent content even
in older folders outside the supported recovery window. Retention may withdraw
their recovery promise; it does not make damaged records clean. Reporting
damage there does not establish damage to newer retained states. This applies
the existing approved needs without changing their text. Cutoff discovery and
report grouping remain system-requirement work.

The [scoped approval stamp](../../archive/last_approved/README.md)
copies only the external registry and records
exactly these 46 newly approved IDs. Existing need approvals are untouched.
The three stakeholder identity records, assumptions, surrogates and downstream
tiers are not approved by this act. Runtime behavior and hooks are unchanged.

Next: prepare [environmental assumptions](../../requirements/assumptions.toml)
for owner review, using the [boundary review worklist](boundary-review.md).
