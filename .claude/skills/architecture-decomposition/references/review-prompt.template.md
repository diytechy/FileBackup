# Scoped convergence review: prompt template

Use after each decomposition pass. Fill the `{...}` fields, save the result as
`prompt.txt` in a fresh output folder, and give it to a reviewer in a fresh
session that has seen none of the earlier rounds. Use a different model family
from the author where you can. Invocation used in FileBackup (Codex; run it in
the background):

```
codex exec -m gpt-6.1-sol -c 'model_reasoning_effort="high"' -s workspace-write -C <out> -o <out>/last-message.md "$(cat <out>/prompt.txt)" < /dev/null > <out>/run.log 2>&1
```

Before trusting the result:
- grep `run.log` for a line of your rendered scope, to confirm the prompt
  arrived intact (backslashes have been mangled before);
- check it actually read the rows. A sandbox failure reports "could not run",
  not "no findings". Retry once, then use another model family and record the
  substitution.

---

You are a fresh CONVERGENCE reviewer of {PROJECT}'s design tier (repo {REPO_PATH}). Earlier review rounds exist, but you see none of them: do NOT read anything under {HISTORY_PATHS}, and never read any OWNER_SCRATCHPAD.md.

Scope: ONLY these, which changed in the last pass:
{SCOPE: the rows (ids), the cells changed, the flows in docs/runtime-flows.md, and, when the pass restructured the tree, "the component tree as a whole" with the two questions (a) do siblings overlap or leave a parent responsibility uncovered (Parnas, Clements and Weiss 1985, goal g), (b) does any value pass between two components with no interface row}
The rows live in docs/requirements/*.toml. You may read any other row as context, and the code to check a claim about today's behaviour.

Stance: convergence, not a fresh hunt. Ask of each scoped item only:
(1) is it internally sound and consistent with its parents and with the forms it uses;
(2) does it contradict any other row or flow (two outcome values, two orders, two forms; an owner or consumer that does not match who produces or uses the value);
(3) for new or changed interfaces: one information kind in one direction, owned by the component that produces or defines it, with a form closed enough to test, and carrying every value the LLRs of each consuming component need.
{EXTRA FOCUS, if any: e.g. "check that the new orders in flows X and Y agree with LLR-...".}
Do not raise style, wording preferences, new corners an unchanged row already had, or a wish for more decomposition beyond the scope. Do not raise the absence of module, code_symbol or component cells on LLRs (they are deliberately forbidden), the Drafted status, or the rule that an interface row may not carry both consumers and requestors.

Deliberate decisions, NOT findings in themselves (raise only an item that contradicts them or states them inconsistently):
- Components describe the system's own internal behaviour; an external system is an external interface, never a component; rows across an external interface resolve to the system root.
- An LLR need not constrain an interface; an unplaced LLR is counted, not refused.
{OWNER DECISIONS AND IMPOSED ARCHITECTURE CONSTRAINTS: list each as a plain sentence, so the reviewer checks consistency with them instead of reopening them.}

Rules for judging: {RULES: e.g. ai-template's pointer-rules.md and spine-questions.md sections 0, 2 and 3, or this repo's prompts/spine-questions.md}. The outcome vocabulary: {OUTCOME VALUES}. The dimensions grammar: name=set{a,b}; name=range[min..max]; name=bool; with @pairwise, @full or @boundaries.

Severity tracks plausibility; dismiss contrived or compromised-host scenarios: BLOCKER (a wrong or contradictory obligation), MAJOR (changes what gets built or tested), MINOR (wording that would mislead a builder or a reviewer reading the flows). Write findings.json (an array of {id, severity, rows, finding, suggested_fix}, ids prefixed {PREFIX}-) and summary.md (counts by severity, one line per finding) into your current working folder, {OUT_DIR}. Write only there.
