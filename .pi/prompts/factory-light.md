---
description: Light-lane review of the current branch (no mission): one fresh reviewer on another model family
---
Light-lane review for change `$1` against base `$2` (ADR-001 D11).

1. Make sure everything to review is committed; if not, stop and ask the human.
2. Run `scripts/factory/workflow.sh light $1 $2` and pass its output verbatim as `subagent({ workflowScript: <output>, context: "fresh", async: false })`.
3. Show the human the verdict at `.scratch/light/$1/verdicts/code.md`. If PASS, commit it; the MR gate checks it.

Never add your own words to the reviewer's task.
