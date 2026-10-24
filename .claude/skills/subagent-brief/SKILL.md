---
name: subagent-brief
description: Use when handing a task to a subagent or another session — write the brief as a seven-part contract (exact delta, output artifact, stopping condition, exclusions, structured return, no further delegation, completion is the artifact) and ask for a six-section return, so the hand-off comes back checkable instead of as a story.
stacks: [any]
domains: [any]
phases: [dev, gate]
tags: [delegation, subagent, brief, handoff, context]
scope: kit
---
**When to use.** You have decided to delegate (whether to is `docs/process.md` §6, "Fan-out"; this skill is only *how*). *Why:* a subagent starts with none of your context, so everything it needs to know is in the brief or nowhere, and a vague brief comes back as confident prose you cannot check without redoing the work.

**Procedure — the brief states seven things.**
1. **The exact delta.** What must be different when it is done, named by file, row or symbol — not a topic to explore.
2. **The output artifact.** The one path (a file, a commit, a report) the result lands in.
3. **The stopping condition.** The observable fact that means done, and the budget past which it stops and reports instead.
4. **The exclusions.** What it must not touch or decide, by name; an unstated boundary is a boundary it will cross.
5. **The return shape.** The six sections below, compact, facts before judgement.
6. **No further delegation.** It does the work itself; a brief it would pass on has lost your context twice.
7. **Completion is the artifact.** A claim of done without the artifact at its path is not done; say so in the brief, so the report cannot stand in for the work.

**The return — six sections, in this order.** (1) What was done. (2) Where the artifact is. (3) What was checked and found clean, so absence of a finding is evidence rather than silence. (4) Findings, each with its location. (5) What was not done, and why. (6) Open questions for the caller.

**Done when:** you can check the return against the seven parts without re-reading the subagent's working, and every claim in it points at something you can open.
