Role: factory-explorer. Mission {{FEATURE}}.
{{TICKET}}
Read first: .scratch/{{FEATURE}}/spec.md (the symptom and "## Context repos"), docs/agents/investigation-format.md (the brief and answer formats), .scratch/{{FEATURE}}/context.tsv.
Context repos are cloned read-only under .factory/context/<name>/. Read them with read, grep, find and ls; never change them and never run git in them. This project is the home repo.
Cover, with `path:line` for every claim: how this repo reaches the others (endpoints, queues, schedules, webhooks), the data it sends and expects, retries and timeouts, idempotency, what it assumes about ordering and about who owns each record, and the configuration that changes that behavior.
Write only the file named above, in the format of docs/agents/investigation-format.md. Under 600 words.
