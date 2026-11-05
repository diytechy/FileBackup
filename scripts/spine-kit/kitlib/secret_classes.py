"""The credential CLASS vocabulary — one home for what a secret PATTERN is,
shared by the hook scanner's always-on enforcement floor
(`check_privacy.py`'s `KEY_RE` / `TOKEN_RES`, SR-017/LLR-017) and the
session-transcript redactor (`agent_common.redact_secrets` / `_SECRET_RES`,
SR-176/LLR-177).

WHY THIS MODULE EXISTS (WI-520, filed by WI-508's alignment pass, `docs/plans/
2026-08-25-remap-alignment.md` §8's `F4`/`M17`). The two pattern sets were
compiled independently in two modules, and driven against five samples, four
disagreed — **in both directions**. The one that mattered: a PEM private-key
block was refused at the commit hook and passed **unredacted** into a
committed transcript, so the durable artifact was less protected than the
ephemeral one it was refused from — the exact hazard SR-176 exists to
prevent, with a different subject. `redact_secrets`' own docstring licenses
passing an *unknown* token shape through; a PEM header is not unknown, it is a
compiled pattern twenty lines over in a sibling module, and that gap — not
exhaustive redaction — is what this module closes.

ONE TABLE, TWO PATTERNS PER CLASS, BOTH DECLARED. `SECRET_CLASSES` is the
class-by-class DECISION, not a merged pattern list: each entry states whether
the enforcement floor scans for it (`scan_pattern`) and whether the transcript
redactor best-effort redacts it (`redact_pattern`). `None` on either side is a
decision, not an omission — the comment beside the entry says why, so presence
or absence is never left to be inferred from which list a literal happened to
land in.

THE ASYMMETRY THIS TABLE MAKES LEGIBLE, STATED ONCE. A missed match has
opposite costs on the two sides: on the enforcement floor a false positive
blocks a contributor's real commit, while on the redactor a false positive
only replaces a few extra characters with `[REDACTED]` in a record nobody is
deprived of (the raw, unredacted stream still lands in gitignored
`out/run-logs/` — `redact_secrets`'s own contract, unchanged). So the redactor
may legitimately run a LOOSER threshold than the floor, or redact a class the
floor does not enforce; the floor must never adopt the redactor's looser
threshold, because that direction turns a false positive into a blocked
contributor. This table does not make redaction exhaustive — `redact_secrets`
stays "deliberately imperfect: unknown token shapes pass through" — it makes
the classes that ARE compiled agree on their membership decision instead of
disagreeing by accident.

`check_privacy.py` and `agent_common.py` DERIVE their working tuples from
`SECRET_CLASSES` (a comprehension over this table), rather than each hand-
copying a subset of it — so a class added here reaches both call sites, or
neither, by construction, and the drift this row exists to fix cannot
reopen by one side forgetting to update its own copy. Both modules keep their
long-standing public names (`KEY_RE`, `TOKEN_RES`, `_SECRET_RES`) as VIEWS over
this table, so no LLR `code_symbol` cell and no call site changes shape.

Pure data — `re` and `typing` only, no sibling import — so it is safe for
`bootstrap.py` to import (the package's one asserted rule) without dragging a
checker into the scaffolder.
"""

from __future__ import annotations

import re
from types import MappingProxyType
from typing import NamedTuple, Optional

__all__ = [
    "SecretClass",
    "SECRET_CLASSES",
    "SECRET_CLASSES_BY_NAME",
]


class SecretClass(NamedTuple):
    """One credential class: its name, and the pattern each side uses (or
    `None`, a deliberate absence — see the per-class comments on
    `SECRET_CLASSES` below).

    `scan_pattern` is the enforcement-floor pattern: precise and tightly
    bounded, because a false positive here blocks a contributor's commit.
    `redact_pattern` is the transcript-redactor pattern: it may equal
    `scan_pattern`, or it may be a deliberately LOOSER variant — never a
    tighter one, since narrowing it would drop a match the redactor already
    catches.
    """

    name: str
    scan_pattern: Optional["re.Pattern[str]"]
    redact_pattern: Optional["re.Pattern[str]"]


# --- The per-class decisions -----------------------------------------------
#
# Order matches `check_privacy.py`'s historical `TOKEN_RES` (private key
# header first, then the five token classes in their original sequence),
# with `generic bearer token` — the redact-only class — last.

SECRET_CLASSES = (
    SecretClass(
        "private key header",
        re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
        re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
        # SAME pattern both sides — the WI-520 fix (was floor-only; the
        # redactor let it through as an "unknown shape"). A PEM header is a
        # known, compiled class, not an unknown one, so there is no argument
        # for the redactor to see less of it than the floor does.
    ),
    SecretClass(
        "github token",
        re.compile(r"ghp_[A-Za-z0-9]{36}"),
        re.compile(r"ghp_[A-Za-z0-9]{20,}"),
        # Redactor threshold is LOOSER (20+ vs the floor's exact 36) — a
        # deliberate asymmetry: over-redacting a transcript costs a reader
        # nothing, while narrowing the floor to 20+ would make it refuse
        # commits on shorter look-alikes it has never flagged before.
    ),
    SecretClass(
        "github fine-grained token",
        re.compile(r"github_pat_[A-Za-z0-9_]{22,}"),
        re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
        # Same shape of asymmetry as `github token`, smaller gap (20 vs 22).
    ),
    SecretClass(
        "slack token",
        re.compile(r"xox[abprs]-[A-Za-z0-9-]{10,}"),
        re.compile(r"xox[abprs]-[A-Za-z0-9-]{10,}"),
        # IDENTICAL pattern both sides. The two modules' literals used to
        # differ only in the character CLASS ORDER (`xox[abprs]-` vs
        # `xox[baprs]-`) — the same five letters, so no sample ever told them
        # apart; stated here as the one pattern it always was.
    ),
    SecretClass(
        "aws access key id",
        re.compile(r"(?<![A-Z0-9])AKIA[0-9A-Z]{16}(?![A-Z0-9])"),
        re.compile(r"AKIA[0-9A-Z]{16}"),
        # Floor is word-bounded (a false positive inside a longer alnum run
        # must not block a commit); redactor is not, and is kept that way
        # deliberately rather than unified onto the bounded form — unifying
        # would NARROW the redactor's existing coverage of an AKIA-shaped
        # run embedded in something longer, which "never weaken an existing
        # pattern" forbids.
    ),
    SecretClass(
        "api secret key",
        re.compile(r"(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{24,}(?![A-Za-z0-9_-])"),
        re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
        # Same shape of asymmetry as `github token`: looser threshold (20 vs
        # 24) and no boundary assertion on the redactor's side.
    ),
    SecretClass(
        "generic bearer token",
        None,
        re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._\-]{25,}"),
        # Redact-only, BY DECISION, not by omission. A bare `Bearer <token>`
        # shape appears constantly in benign contexts (API examples, curl
        # commands, documentation) with no distinguishing marker the way
        # `ghp_`/`sk-`/`AKIA`/a PEM header carry one, so adding it to the
        # commit-blocking floor risks refusing ordinary documentation edits.
        # The redactor may still over-redact it in a transcript, because a
        # false-positive redaction there costs a reader nothing.
    ),
)

#: Lookup by class name — the label every finding/redaction already carries.
#: Immutable: built once from `SECRET_CLASSES`, never mutated in place.
SECRET_CLASSES_BY_NAME = MappingProxyType({cls.name: cls for cls in SECRET_CLASSES})
