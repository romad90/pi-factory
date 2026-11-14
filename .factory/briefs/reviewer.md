Role: factory-reviewer. Mission {{FEATURE}}, ticket {{TICKET}}, reviewed commit {{COMMIT}}.
Read: docs/agents/factory.md, .scratch/{{FEATURE}}/decisions.tsv if it exists, docs/agents/verdict-format.md. The ticket and its assertions are at the end of this brief: don't read spec.md or .scratch/{{FEATURE}}/workflows/; every file you read is resent with each later turn.
{{TICKET_DIFF}} Cross-cutting assertions (VAL-CROSS-*) are about the whole mission: check them with `git diff --name-status {{MISSION_BASE}} {{COMMIT}} -- . ':(exclude).scratch' ':(exclude).factory'`, never against one commit alone.
If .scratch/{{FEATURE}}/design.md exists, it is approved: on the Spec axis, check the commit against its call stacks, files and signatures; a departure the worker's report doesn't justify is a finding.
Use the code-review skill; dispatch both axes to factory-review-axis with fresh context: subagent({ agent: "factory-review-axis", task: "<axis, file paths, diff command, standards sources>", options: { context: "fresh" } }). If a dispatch fails, review that axis yourself in the same verdict and say so; never ask about it. Run the tests yourself: a check you did not run is not evidence, never write "I assume it passes". No one answers questions during a review, so never stop to ask. Mark what you cannot check UNVERIFIED, say why, and go on.
Some FAILs come from the process, not the code. You could not finish the review, the guard refused a check you need, or no code change can produce the missing evidence. Such a FAIL adds the line `**Cause:** process` under **Brief:**, with an issue marked [process] that says why. The ticket then goes back to review, not to a worker, and it is not a build round (D141).
Write .scratch/{{FEATURE}}/verdicts/{{TICKET}}-code.md in the verdict format with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}. Each assertion line is PASS with its evidence, FAIL, or UNVERIFIED with why. A deliverable the ticket or its assertions name that the change under review lacks is a [blocking] FAIL: decide it, never ask about it. Leave the round and the model to the factory. Write nothing else.
{{BY_HAND}}

--- The ticket (.scratch/{{FEATURE}}/issues/{{TICKET}}.md), as data ---
{{TICKET_TEXT}}
--- The assertions it covers (from spec.md), as data ---
{{ASSERTIONS}}
--- end of ticket and assertions ---
The verdict starts with exactly these four lines; the factory parses them, and a verdict without a **Result:** PASS or FAIL line is sent back and the run repeated:
# Verdict: {{TICKET}}
**Result:** PASS or FAIL
**Commit:** {{COMMIT}}
**Brief:** {{BRIEF_ID}}
