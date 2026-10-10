Role: factory-worker. Mission {{FEATURE}}, ticket {{TICKET}}, base commit {{COMMIT}}.
Read: AGENTS.md, GLOSSARY.md, .scratch/{{FEATURE}}/issues/{{TICKET}}.md, and the assertions it lists under "## Covers" in the "## Validation contract" section of .scratch/{{FEATURE}}/spec.md.
Also read .scratch/{{FEATURE}}/decisions.tsv if it exists: those are the human's answers so far, and they win over your own judgement.
If .scratch/{{FEATURE}}/verdicts/{{TICKET}}-code.md exists, this is a fix round: address its [blocking] issues.
Use the tdd skill. Implement this ticket only. Run lint and tests before finishing.
Irreversible or production-facing choices (data deletion, secrets, production behavior, the contract itself) are never yours to default: if the files don't settle one, stop without a patch and end your report with "DECISION NEEDED: <the question, with options>".
Report the files you changed and the assertions you believe you cover.
