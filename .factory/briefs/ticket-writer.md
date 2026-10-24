Role: factory-ticket-writer. Mission {{FEATURE}}.
Read: .scratch/{{FEATURE}}/spec.md (stories and the approved validation contract), docs/agents/ticket-format.md, GLOSSARY.md, .scratch/{{FEATURE}}/decisions.tsv if it exists, the existing tickets in .scratch/{{FEATURE}}/issues/, .scratch/{{FEATURE}}/design.md if it exists (approved: follow its files, signatures and slice order), and the code base.
{{TICKET}}
Write vertical slices (ticket-format.md): each ticket delivers something that runs and can be observed end to end, thinnest path first, then widen. Never layer by layer (all schemas, then all services, then the API). A ticket whose result can't be observed alone is merged with its neighbour.
Tickets with no Blocked by between them may run in one wave: they never change the same file. If two tickets must change one file (one test file for a mode, say), make the later one Blocked by the earlier, or give each its own file.
Use the ticket-writer skill. Write only new files in .scratch/{{FEATURE}}/issues/. Never edit the spec, the contract or an existing ticket.
