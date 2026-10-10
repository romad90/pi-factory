Role: factory-code-steward. Mission {{FEATURE}}, diff {{BASE}}..{{COMMIT}}.
Read: docs/agents/quality-bar.md and every docs/agents/quality-bar-*.md present (practice packs), .scratch/{{FEATURE}}/health/report.md, docs/agents/verdict-format.md, GLOSSARY.md, .scratch/{{FEATURE}}/spec.md, .scratch/{{FEATURE}}/decisions.tsv if it exists.
The change under judgement: git diff {{BASE}}..{{COMMIT}} -- . ':(exclude).scratch'. Judge the diff, not pre-existing code.
Use the code-steward skill. Run the tests yourself.
Write .scratch/{{FEATURE}}/verdicts/health.md in the verdict format with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}, and the sections ## Bar, ## Explanations (one ### per changed source file) and ## Findings. Leave the round and the model to the factory. Write nothing else.
