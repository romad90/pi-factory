# P4. Director and triggers

**Status:** draft · **Effort:** L · **Depends on:** P1 (shared budget), P2 (a lead that doesn't drift)

## Problem

Every mission starts with a person typing `/factory`, and one lead serves one repo at a time on one laptop. The goal in [INTENT.md](../INTENT.md) is the opposite: maintenance and correction running in the background, the team working on what was out of reach. That needs missions that start from events, and something that decides which ones run, where, and with which budget.

## Proposal

### Triggers

An event becomes a mission of a given intent, with an autonomy level set by policy, not by the agent.

| Trigger | Mission | Runs alone until | Human gate |
|---|---|---|---|
| Schedule | Maintenance sweep: dependency updates, health ratchet, standards gaps, dossier refresh (P3) | the MR | MR review |
| Webhook: CI red on the main branch | Fix lane (D41): blast radius, one reviewer | the MR | MR review |
| Webhook: merge request opened | Light review (D40) | the verdict | none |
| Incident (outage, error spike) | Bugfix: **reproduction test first**, then the fix | the reproduction | approve the fix plan |
| Customer feedback | Draft spec from the feedback | the draft | interview and G1 |
| Proactive bug hunt | Exploration: produces tickets, never code | the ticket list | triage |
| Another agent | Handoff with its evidence attached | depends on the source's intent | as above |

### Director

One director per team, above the leads:

- **Intake:** receives events, deduplicates them, gives each an intent and a priority.
- **Dispatch:** starts one lead per repo (P2's script), never two on the same repo.
- **Budget:** allocates the team's gateway budget across leads (P1's `usage.tsv` and caps), and holds work when the budget is spent.
- **WIP limits:** a cap on missions in flight, per repo and per team.
- **Reporting:** one daily summary: missions started, waiting on a human, merged, escalated; human time spent; budget used.

It never writes code, never approves a human gate, and never changes a policy. Policies (which trigger may run which intent, up to which gate) are files in a repo, reviewed like code.

### Where it runs

Phase 1 stays on a laptop: the director is a script reading an event queue (a directory, then a webhook receiver) and starting leads in worktrees. Phase 2 moves to a CI runner or a small service when the team trusts it, with the sandbox constraints of [agent-sandboxing](../research/agent-sandboxing.md).

## Trade-offs

| For | Against |
|---|---|
| Maintenance happens without anyone starting it: the goal itself | An autonomous system that opens MRs creates review load. If the MRs aren't trusted, the team drowns. The WIP limit and the evidence report (S3) are the brakes. |
| Budget and priorities are decided in one place, visibly | One more component to secure: it holds credentials for several repos and gateways. It needs its own key per gateway, scoped, and no production access by default |
| Incidents get a reproduction test within minutes | A wrong triage wastes a mission. Start with read-only intents (exploration, light review) and widen per trigger as the retro shows they hold |
| A daily report makes the factory's value visible to the team | Building it before P1 and P2 hold would automate failures: a drifting lead started by a cron job fails at night with nobody watching |

## What it unlocks

- **Step 3 on the [ladder](../LADDER.md):** humans supervise outcomes and exceptions, not steps.
- **The shift of work INTENT.md describes:** correction and maintenance in the background, measured in human hours given back.
- **Cross-repo work:** a dependency upgrade across a monorepo's folders, each with its own lead, coordinated by one director.

## Perspective

The order matters more than the design. Each trigger should be switched on only when the lane it starts has held on missions run by hand: light review first (read-only), then the fix lane, then scheduled maintenance once P3 has proven itself, and incidents last. The director grows by adding triggers, not by adding intelligence: it routes, budgets and reports; the judgment stays in the lanes and with the humans at the gates.

## Plan

1. Policy file format: trigger → intent → autonomy level. **S**
2. Director phase 1: event directory, dispatch to `factory-run.sh` (P2), WIP limits, daily report. **M**
3. First trigger: merge request opened → light review. **S**
4. Then CI red → fix lane; schedule → maintenance sweep (after P3). **M**
5. Phase 2 hosting, after a retro on phase 1. **L**

## Open questions

- Where do events come from first: the forge's webhooks, the CI, or the incident tool? Proposed: the forge, since light review is the safest first trigger.
- Does the team want one director per team or per domain (monorepo folder owners)?
- How is the director itself supervised? Proposed: its daily report goes to a channel the team reads, and every mission it starts is visible as a branch and a `.scratch/` folder like any other.
