# Practice packs

The factory is agnostic: it builds and maintains bots, APIs, front ends, batch jobs, in any language. What it knows about **your kind of software** comes from content, never from code: a pack is a few markdown files that the existing roles already read.

| File in a pack | Read by | Effect |
|---|---|---|
| `docs/agents/contract-checklist-<pack>.md` | contract author and critic (G1) | the contract gets assertions for what this kind of software must do (errors, idempotency, exit codes…) |
| `docs/agents/quality-bar-<pack>.md` | code steward (G5) | extra `QB-<PACK>-NN` items judged on every mission's diff |

Install with `scripts/factory/install-into.sh <repo> --pack api` (repeatable). Pack files are **repo-owned**: copied once, then yours to edit. Company taste that applies everywhere still goes in `AGENTS.md`.

| Pack | For |
|---|---|
| [`api`](api/) | HTTP APIs. Stripe-inspired: one error shape, idempotency keys, cursor pagination, request IDs, additive changes. Items marked **Public** only apply to APIs used by third parties. |
| [`batch`](batch/) | Scheduled jobs and batch bots: exit codes, safe re-runs, caps, dry-run, stop on upstream failure. |
| [`bot`](bot/) | Conversational bots: routing, tools, prompt injection, multi-turn. |

**Enforce or not?** On a blank page, install the pack: conventions are cheapest before the first endpoint, and every item stays amendable at G1. On an existing code base, consistency with what is there beats any ideal: prune the items that contradict it before the first mission. The steward judges the diff, never the past.

**Write a pack:** two files, items that are checkable on a diff or as an assertion, stable IDs. Keep it short; a pack nobody reads is noise.
