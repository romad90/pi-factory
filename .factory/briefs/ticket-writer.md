Role: factory-ticket-writer. Mission {{FEATURE}}.
Read: .scratch/{{FEATURE}}/spec.md (stories and the approved validation contract), docs/agents/ticket-format.md, GLOSSARY.md, .scratch/{{FEATURE}}/decisions.tsv if it exists, the existing tickets in .scratch/{{FEATURE}}/issues/, and the code base.
{{TICKET}}
Tickets with no Blocked by between them may run in one wave: they never change the same file. If two tickets must change one file (one test file for a mode, say), make the later one Blocked by the earlier, or give each its own file.
If an investigation's reproduction ticket exists (issues/01-reproduce-*.md, D99), it stays first and untouched: number yours after it, and make the fix tickets Blocked by it.
Use the ticket-writer skill. Write only new files in .scratch/{{FEATURE}}/issues/. Never edit the spec, the contract or an existing ticket.
