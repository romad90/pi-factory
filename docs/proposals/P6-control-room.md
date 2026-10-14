# P6. Control room: a hosted factory, a dashboard, events from operations

**Status:** draft · **Effort:** L · **Depends on:** P2 (scripted lead), P4 (director and triggers), P5 (improvement PRs); step 3 of the [ladder](../LADDER.md)

## Problem

Today the factory runs on one laptop, one mission at a time, and its state is read by running `next.sh` in a terminal. That is enough to build it. It is not enough for a team:

- **Nobody else can see what is running.** Status, rounds, open questions and costs live in `.scratch/` files and in one person's terminal.
- **Work only starts when a person types `/factory`.** The events that should start work (an alert in production, a labeled issue, a red pipeline) reach people, not the factory.
- **Production knowledge doesn't reach the code.** An SRE agent can watch the observability platform and recognize a known problem from the team's knowledge base articles (KBAs), but nothing turns that into a reproduction test and a fix.

## Proposal

Three parts. Each is useful alone; together they are step 3: humans supervise outcomes and exceptions, not steps.

### 1. A hosted factory

The director (P4) and its leads (P2, scripts) run in a **dedicated namespace**, not on a laptop:

- one runner per repo, never two on the same repo;
- its own credentials per gateway and per forge, scoped, with **no production write access** (reading the observability platform is allowed, deploying is not);
- mission state stays where it is today: `.scratch/` in the repo, committed. The hosted factory adds no new source of truth, so a mission can still be resumed on a laptop.

### 2. Events in, through labeled issues

Every trigger becomes an **issue in the forge with a label**, and the label decides the lane. The issue is the audit trail: who asked, why, what the factory did, the PR it opened.

| Source | Becomes | Label → lane |
|---|---|---|
| A person | an issue they write | `factory:feature`, `factory:fix`, `factory:maintenance` |
| SRE agent, alert matches a KBA | an incident issue citing the KBA, the alert and sample events | `factory:incident` → reproduction test first, then fix PR |
| SRE agent, alert matches nothing known | an incident issue, investigation only | `factory:investigate` → findings, no code |
| CI red on the main branch | an issue linking the failed job | `factory:fix` |
| Strategist (P5) | an improvement candidate, once a person picks it | `factory:improve` |

The SRE agent never calls the factory directly. It writes an issue, like a person would. One door in, one policy (P4's autonomy table), one place to read what happened.

For an incident, the issue carries what the KBA says to do first (the runbook), what the observability platform shows (error rate, first occurrence, the release in production), and the suspected change. The factory's lane follows the incident lifecycle:

`detected → investigating → root cause found → fixing → ready for review → deployed`

The factory moves an incident up to **ready for review**: a reproduction test that fails on the main branch, a fix that makes it pass, the full suite green, a draft PR. **Deploying stays a human action**, always: the factory says what it would ship and waits. If a person declines, it records the decision and doesn't ask again.

### 3. A dashboard

One page for the team, read-only by default:

- **Missions and incidents** by repo: lane, step, ticket table, rounds, who is waiting on whom.
- **Human queue:** every open question, approval and escalation in one list, with the decision buttons (approve, decline, answer). Each decision is written where the factory already reads it (`decisions.tsv`, `/factory-decide`), so the page adds no new state.
- **Cost and quota:** requests and tokens per provider and role (P1's `usage.tsv`), production budget left.
- **Health:** retro findings, health baseline trend, improvement PRs open and merged (P5).
- **Event feed:** what came in, what it became (issue, mission, nothing), and why.

Every running phase saves a checkpoint (the factory already commits mission state), so closing the page or restarting the runner never loses work; an approval waits on its checkpoint until someone answers.

## Trade-offs

| For | Against |
|---|---|
| The team sees the factory's work without asking the person who runs it | A hosted service to secure and operate: credentials for several repos and gateways. Starts with read-only intents, as P4 says |
| Incidents arrive with a reproduction test and a fix, minutes after the alert | A wrong KBA match wastes a mission. Low-confidence matches go to `investigate`, which writes no code |
| Labeled issues are an audit trail the team already knows how to read | Labels become an API: renaming one breaks a lane. The label list lives in the policy file, checked at install |
| One human queue instead of decisions scattered across terminals | Easy to approve from a page without reading. The approval card shows the evidence (diff, tests, rounds) before the button |
| Deploying stays human: the factory can't break production by itself | Mean time to recovery still includes a human. That's intended until the incident lane has a track record |

**Rejected alternative:** the SRE agent fixing code itself. It would need write access to repos and the factory's gates would be bypassed. Keeping one door (the issue) means every change goes through the same contract, tests and review.

## What it unlocks

- **Step 3 of the ladder:** the factory runs continuously; people handle exceptions and decisions.
- **Incidents to tested fixes:** the knowledge in the KBAs becomes tests in the code, so a known incident can't come back unnoticed.
- **A shared view for the team and its management:** what the factory did this week, what it cost, what is waiting on whom.

## Perspective

This is where the earlier proposals pay off. P1 makes gateways dependable, P2 makes the loop deterministic, P3 freezes behavior, P4 routes events, P5 improves the code. P6 puts them where a team can watch them and plugs in operations. The order matters: hosting a factory whose lead still drifts, or whose patches can touch frozen code, would only make failures faster and more visible. P6 comes after the retro shows those hold.

## Plan

1. Label policy file and the issue intake in the director (`factory:*` labels → lanes). **S**
2. Read-only dashboard from the mission files, served next to the director. **M**
3. Human queue on the dashboard, writing decisions through the existing scripts. **M**
4. SRE agent integration: incident issue format (KBA, alert, events, suspected release), `investigate` and `incident` lanes. **M**
5. Hosting in a dedicated namespace: runner per repo, scoped credentials, no production write. **L**

## Open questions

- Who owns the SRE agent's KBA matching: the SRE team or the factory? Proposed: the SRE agent, since it already reads the KBAs; the factory trusts the issue.
- Does the dashboard need write actions in phase 1, or is read-only plus the CLI enough? Proposed: read-only first.
- How long may an approval wait before it is escalated to someone else on the team?
