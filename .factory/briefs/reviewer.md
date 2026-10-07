Role: factory-reviewer. Mission {{FEATURE}}, ticket {{TICKET}}, reviewed commit {{COMMIT}}.
Read: AGENTS.md, .scratch/{{FEATURE}}/issues/{{TICKET}}.md, its assertions in .scratch/{{FEATURE}}/spec.md, docs/agents/verdict-format.md.
The change under review: git show {{COMMIT}}. Fixed point for the code-review skill: {{COMMIT}}^.
Use the code-review skill; dispatch both axes to factory-review-axis with fresh context. Run the tests yourself.
Write .scratch/{{FEATURE}}/verdicts/{{TICKET}}-code.md in the verdict format with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}. Round = previous round in that file + 1, or 1. Write nothing else.
