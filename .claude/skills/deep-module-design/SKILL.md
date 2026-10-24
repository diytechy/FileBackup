---
name: deep-module-design
description: Use when a function or module grows past a complexity or size budget, when adding a module, a parameter or a flag, or when splitting code — design deep modules (a small interface over a lot of behaviour) and decompose outward, instead of shallow wrappers, pass-through layers or mode flags.
stacks: [any]
domains: [any]
phases: [dev]
tags: [design, complexity, modularity, refactoring, interfaces]
scope: kit
---
**When to use.** A complexity or module-size ratchet fires, a function reaches for another flag, or a split is on the table. *Why:* the cost of a module is its interface, and its value is the behaviour behind it. A split that only moves lines makes more interfaces for the same behaviour, and the reader pays for each one.

**Procedure.**
1. **Name the one decision the module hides.** If its interface says as much as its body (a pass-through, a getter per field, a wrapper renaming a call), merge it back; if it hides two unrelated decisions, split along the decision, not the line count.
2. **Decompose outward.** Lift a branch into a sibling function or a new module with a name a caller can read, never a nested `def`. Express a ladder of cases as a data table. Define an error out of existence where the caller cannot act on it, so the branch disappears.
3. **Replace flag pairs with a state.** Two booleans that are never both true are one enum; a function taking two or more flags is usually two functions or one mode. A call site passing a bare `True` is the symptom to look for.
4. **Pull the shared stage out once.** Where two paths run A→B→C and A→B→D, extract A→B (PROCESS.md §3, the 0→A→B rule) unless it is a line or two; do not fuse the two paths behind a mode flag to lower a count.
5. **Move structure in its own commit.** A behaviour-preserving move lands before the behaviour change it enables, so each diff is reviewable as one kind of change.
6. **Done when:** the measure is back within its budget by a smaller interface, not by a stamped exception, and the move commit's tests pass unchanged.

**Knowledge:** Ousterhout, *A Philosophy of Software Design*, on deep modules and defining errors out of existence; the kit's complexity sensor (`scripts/check_complexity.py`) and the readability report's measures (`scripts/check_readability.py`).
