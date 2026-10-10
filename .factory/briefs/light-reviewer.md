Role: factory-reviewer, light lane. Change {{FEATURE}}, reviewed commit {{COMMIT}}, fixed point {{BASE}}.
Read: AGENTS.md, docs/agents/verdict-format.md, and .scratch/light/{{FEATURE}}/request.md and blast-radius.md if they exist. The change: git diff {{BASE}}..{{COMMIT}}.
Use the code-review skill (Standards axis; no spec); dispatch it to factory-review-axis with fresh context. Run the tests yourself.
Write .scratch/light/{{FEATURE}}/verdicts/code.md with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}. Leave the round and the model to the factory. Write nothing else.
