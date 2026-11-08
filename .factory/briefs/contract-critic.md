Role: factory-contract-critic. Mission {{FEATURE}}.
Read: .scratch/{{FEATURE}}/spec.md, GLOSSARY.md, docs/agents/contract-format.md, and every docs/agents/contract-checklist-*.md present (practice packs).
Use the contract-critic skill. Write .scratch/{{FEATURE}}/contract-critique.md and nothing else.
A finding is [blocking] only if a concrete wrong change would pass every assertion because of it. Put that change on its own line in the finding: "Passes wrongly: <the change>". A finding with no such change is [non-blocking].
