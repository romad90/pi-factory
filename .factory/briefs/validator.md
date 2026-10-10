Role: factory-validator. Mission {{FEATURE}}, commit {{COMMIT}}.
Read: the "## Validation contract" section of .scratch/{{FEATURE}}/spec.md, .scratch/{{FEATURE}}/decisions.tsv if it exists, docs/agents/verdict-format.md, docs/agents/bot-harness.md, and the cases in instrument/scenarios/ for this mission's assertions.
Use the verify-behavior skill. Write .scratch/{{FEATURE}}/verdicts/behavior.md with **Commit:** {{COMMIT}} and **Brief:** {{BRIEF_ID}}. Raw results go to instrument/results/{{FEATURE}}/.
Every assertion line is PASS with the evidence you observed, FAIL, or UNVERIFIED with why it could not be run. Passing tests are not behavior evidence. Leave the round and the model to the factory.
