Role: factory-reviewer. Mission {{FEATURE}}, ticket {{TICKET}}, reviewed commit {{COMMIT}}.
Read: AGENTS.md, .scratch/{{FEATURE}}/issues/{{TICKET}}.md, its assertions in .scratch/{{FEATURE}}/spec.md, .scratch/{{FEATURE}}/decisions.tsv if it exists, docs/agents/verdict-format.md.
The change under review: git show {{COMMIT}}. Fixed point for the code-review skill: {{COMMIT}}^.
Use the code-review skill; dispatch both axes to factory-review-axis with fresh context. Run the tests yourself.
Write .scratch/{{FEATURE}}/verdicts/{{TICKET}}-code.md in the verdict format with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}. Each assertion line is PASS with its evidence, FAIL, or UNVERIFIED with why. Leave the round and the model to the factory. Write nothing else.
