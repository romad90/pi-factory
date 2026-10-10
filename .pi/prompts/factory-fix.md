---
description: Fix lane for small changes: blast radius, checks, one fresh reviewer (no mission)
---
Arguments: `$@`. Forms:
- `<slug> start "<what>" [--mission <feature>]`
- `<slug> check`

`start`: run `scripts/factory/fix.sh start <slug> "<what>" [--mission <feature>]`, show the output and stop. The human (or the main session, on request) makes the smallest change and commits it.

`check`: run `scripts/factory/fix.sh check <slug>`. If it exits non-zero, show the output and stop (blocked: needs a mission or a fix ticket, or checks failed). Otherwise run the `workflow.sh light ...` command it prints, pass its `WORKFLOW_FILE` with `subagent({ workflow: "<path>", context: "fresh", async: false })`, then `scripts/factory/collect.sh --light <slug>`, and show the verdict summary.

Never make the change yourself unless the human asks you to, and never review it yourself.
