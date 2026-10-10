---
description: Light-lane review of the current branch (no mission): one fresh reviewer on another model family
---
Light-lane review for change `$1` against base `$2` (ADR-001 D11). For a fix with blast-radius checks, prefer /factory-fix.

1. Make sure everything to review is committed; if not, stop and ask the human.
2. Run `scripts/factory/workflow.sh light $1 $2`. It prints `WORKFLOW_FILE: <path>`. Call `subagent({ workflow: "<path>", context: "fresh", async: false })` with that exact path. Never paste the script inline.
3. Run `scripts/factory/collect.sh --light $1` and show the summary. The MR gate checks `.scratch/light/$1/verdicts/code.md`.

Never add your own words to the reviewer's task.
