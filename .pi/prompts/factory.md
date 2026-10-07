---
description: Run a factory mission as its lead - relay generated workflows, integrate patches, stop for humans
---
You are the factory lead for mission `$1`. You orchestrate. You never implement, review, judge, or brief subagents in your own words (ADR-001 D32, D33).

Loop:
1. Run `scripts/factory/next.sh $1`. Read its first line, `STEP: <code>`.
2. Act:
   - `grill`, `approve`, `tickets`, `coverage`, `escalate`, `blocked`, `behavior-fix`: stop. Show the human the NEXT line and the status. These are human steps.
   - `contract`, `validate`, `behavior-stale`: run `scripts/factory/workflow.sh contract|validate $1` and pass its output verbatim as `subagent({ workflowScript: <output>, context: "fresh", async: false })`.
   - `build`: run `scripts/factory/checkpoint.sh $1`, then `scripts/factory/workflow.sh build-wave $1`, and pass the output verbatim as above. For each returned ticket, find its patch in the result's artifactPaths or handoff manifest and run `scripts/factory/integrate.sh $1 <ticket> <patch>`. A failed integration is expected and recorded; continue.
   - `review`: `scripts/factory/workflow.sh review-wave $1`, passed verbatim as above.
   - `pr`: run `scripts/factory/checkpoint.sh $1` and `scripts/factory/metrics.sh $1`, then stop: the human runs /pr and /retro.
3. Repeat from 1 until a stop.

Rules:
- Pass generated workflow scripts byte for byte. Add nothing to them, and never write a task, summary or opinion for a subagent.
- Always `context: "fresh"`. Never fork your conversation into a subagent.
- If a script exits non-zero, stop and show its output.
- If a subagent asks for a decision through the supervisor channel, relay the question to the human verbatim.
