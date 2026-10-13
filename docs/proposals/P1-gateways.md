# P1. Several gateways, a fallback chain, a production budget

**Status:** draft · **Effort:** M · **Depends on:** nothing

## Problem

The factory assumes one model gateway. Teams often have several keys: one or two sandboxes, a dev environment, and a production gateway with a high SLA that other teams also depend on.

Evidence from mission 2:

- One key, a quota of 10 requests and 45,000 tokens per minute per model. The lead and a worker on the same model exhausted it together. Three tickets escalated in two minutes on 429s.
- The probe added in D59 reads a single `FACTORY_GATEWAY_URL` from `commands.env`. That duplicates what Pi already knows (its provider config) and can only describe one gateway.
- pi-subagents removed `fallbackModels`. When a provider fails, nothing switches to another one: the mission pauses (D58) and waits for a human.

## Proposal

**1. Pi's provider config is the single source of truth.** Each gateway is a Pi provider (`sandbox-a`, `sandbox-b`, `dev`, `prod`), with its own base URL and its own key variable, declared once in Pi's `models.json`. The factory never declares a gateway again. `models-probe.mjs` reads that file and probes every provider an agent can use.

**2. A fallback chain per role, in the models profile.**

```json
"chains": {
  "factory-worker":   ["sandbox-a/gpt-oss-120b", "sandbox-b/gpt-oss-120b", "prod/gpt-oss-120b"],
  "factory-reviewer": ["sandbox-a/gemma-4-31b-it", "dev/gemma-4-31b-it"]
}
```

On a provider error (429, 5xx, timeout), D58 records no round. Instead of only pausing, the factory moves that role to the next link of its chain, rewrites the agent's `model:` line, and relaunches the wave. When the chain is exhausted, it pauses as today.

**3. A budget on production.** A cap per day and per provider (requests and tokens), in the profile:

```json
"budgets": { "prod": { "requestsPerDay": 300, "tokensPerDay": 2000000 } }
```

Each wave appends its usage to `.factory/usage.tsv` (provider, role, requests, tokens, from the run metadata). Before using a capped provider, the factory checks what is left. When the cap is reached, that link is skipped. A role whose chain has no production link (the judges, for example) simply waits.

**4. The probe follows the chains.** It probes every link of every chain, so a fallback is known to work before it is needed.

## Trade-offs

| For | Against |
|---|---|
| Production protected by a mechanical cap, not by discipline | A fallback can change the model family mid-mission. The family rule (D31) must be checked on every link, not only the first: a chain that drifts into the judges' family is refused at install. |
| Missions keep moving when a sandbox is exhausted | Results from different providers are less comparable: a ticket built on prod after two rounds on sandbox mixes two behaviors. The verdict records which provider ran, so metrics stay honest. |
| One place for gateways (Pi), no drift between Pi and the factory | The factory depends on the shape of Pi's `models.json`. If Pi changes it, the probe breaks. Mitigation: read it through one small parser, with a test fixture. |
| Usage becomes visible per role and provider | `usage.tsv` relies on what pi-subagents reports per run. If it doesn't report tokens, only requests can be capped. To verify before building. |

**Rejected alternative:** a proxy in front of all gateways that routes and caps. More robust, but it's a service to run and secure, and the factory stays a set of scripts on a laptop (D27). Reconsider when the director (P4) runs on shared infrastructure.

## What it unlocks

- **Mission 2 can finish** without a quota raise: two sandboxes double the throughput, production covers peaks under a cap.
- **Request accounting (X10)** comes for free from `usage.tsv`: cost per accepted ticket, by role and by provider. That's the denominator [INTENT.md](../INTENT.md) asks for.
- **P4 (director)** needs it: a director allocates a shared budget across several leads.

## Perspective

Today a quota incident stops a mission and costs a human an evening. With chains and budgets it costs a few minutes of degraded throughput, and the production gateway can't be over-used by accident. The next step after this one, when the factory runs on shared infrastructure, is a routing proxy owned by the platform team.

## Plan

1. Parse Pi's provider config; probe every provider an agent uses (replaces `FACTORY_GATEWAY_URL`). **S**
2. `chains` in the models profile; `models-lint` checks the family rule on every link. **S**
3. `record-no-patch.sh --provider` advances the role to its next link instead of only pausing; the verdict and `usage.tsv` record the provider. **M**
4. `budgets` and the cap check before a wave. **S**

## Open questions

- Does pi-subagents report tokens per run, or only requests? It decides whether budgets can be in tokens.
- Should the chain advance for the whole wave, or only for the failing role? Proposed: only the failing role.
- Does a team want production reserved for some roles only (the lead, the steward), or never for workers? The profile allows both; the default is to leave production out of every chain until a person adds it.
