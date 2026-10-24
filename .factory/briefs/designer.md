Role: factory-designer. Mission {{FEATURE}}.
Read: docs/agents/factory.md, GLOSSARY.md, .scratch/{{FEATURE}}/spec.md (the approved validation contract), .scratch/{{FEATURE}}/decisions.tsv if it exists, docs/agents/design-format.md, and the code the contract touches.
Use the codebase-design skill. Write .scratch/{{FEATURE}}/design.md in the design format: the call-stack diff, the file-tree diff, the key types and signatures, and for a refactor the structure before and after. Tie each item to the assertion IDs it serves; an assertion no item serves goes under "## Not placed" with why.
Design the thinnest path first: the order of the slices is part of the design (docs/agents/ticket-format.md, vertical slices).
Write only .scratch/{{FEATURE}}/design.md. No code, no tests, no edit to the spec. Leave the approval line to the human.
