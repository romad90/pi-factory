# P19. Proactive systems: work that starts before anyone sits down

**Status:** draft, later: only once the core engine meets its entry criteria (below) · **Effort:** L, one candidate at a time · **Depends on:** P12 (durable runner), P16 (issue in, MR out), P14 (measured runs), P4 (director)

## Problem

Today every piece of factory work starts with a person: someone writes a spec, types `factory run`, answers at a gate in one terminal. Inside a mission the factory is near the loop: a scripted lead, gates in code, a handful of human decisions. At both ends, a person is the trigger and the transport, and the run stops when that person's terminal closes.

A talk on agentic engineering in October 2026 ("Elite agentic engineers are leaving the loop") drew the target cleanly. **In the loop**, you prompt. **Near the loop**, you approve, and work happens before and after you check in. **Out of the loop**, you observe. The architecture it describes has three parts:

- **triggers**: cron, webhook, log event, ticket, CLI, browser, another agent;
- **one API**: every trigger enters the same way;
- **a durable agent in a sandbox**: its own compute, always on, isolated, and it survives crashes, restarts and closed laptops.

Proposals P4, P6, P12 and P16 each build a part of that. This proposal lists **what to make proactive, in which order, and when it's allowed to start**, so that each one is chosen by the data, not by enthusiasm.

## The architecture, in our terms

| Talk | Factory |
|---|---|
| Triggers | Labeled forge issues (P16), a schedule, alerts through an SRE agent (P6), the factory's own analyst (P15) |
| API | One intake: an event becomes a work item file under `.scratch/<work>/request.md` with its source, its lane and its author; nothing starts a mission any other way (P4's one door) |
| Durable agent | `run.sh` on a durable runner (P12): it stops at a gate, waits, and resumes when the answer lands from anywhere |
| Sandbox | Worktrees, the command guard, network rules and scrubbed credentials today; separate compute when a shared runner exists (P6) |
| Memory | Files in git, the run archive, `decisions.tsv`: already there |

## The filter: one component between the triggers and the door

Every trigger produces far more events than work. One component sits in front of the intake for all of them (traffic, CI results, advisories, audit findings, news about our tools), and sorts each event into three outputs:

| Output | Means | What happens |
|---|---|---|
| **Noise** | Nothing to learn or do | Dropped, counted |
| **Fact** | True and worth keeping, nothing to do now | Recorded: baselines, trends, the archive |
| **Signal** | Something to act on | A work item through the one door |

An event is **signal only when it can be acted on**: it maps to a lane (a P19 candidate), it has an owner (this repo, another team, the on-call), and the lane has an outside check that will say whether the action worked. Anything else is a fact, however alarming it looks: that keeps the factory from opening work it can't verify.

The filter is built like detection above: rules and signatures first, rates against baselines, a model only for what is left and optional. Each signal carries its reason and its evidence; each human label that overturns a decision becomes a rule. Measured by its precision (signals that led to merged work, from the labels and the forge) and by the share of events decided without a model.

## Entry criteria: when the engine is efficient enough

A proactive system multiplies whatever the engine does, its mistakes included. None of the candidates below starts until the measured data (P14, `metrics --all`) shows, over the last three missions:

- human decisions per mission at or under 5;
- no escaped defect: nothing reverted or fixed after merge because of a factory change;
- first-pass rate on tickets stable or rising, with no mission escalating more than one ticket in three;
- `factory setup` green on the target project, and the durable runner (P12) proven by a kill-and-resume test.

And per lane: the lane's own gates must decide the outcome without a model's opinion (tests, a type check, a scanner), or a human stays at the gate.

## Candidates

Ordered by how much the outcome is decided by code, which is what makes it safe to leave unattended. **Position** is where the human sits: near (approves), out (observes).

| # | Candidate | Trigger | Raw material | Output | Outside check | Position |
|---|---|---|---|---|---|---|
| 1 | **Dependency and vulnerability bumps** | Schedule, or a new advisory | Lockfile, advisory database, the project's tests | One MR per bump, with the advisory | Tests and type check green; the scanner no longer reports it | near, then out for patch versions |
| 2 | **Red main branch** | CI webhook: the target branch fails | The failed job's log, the commit range since the last green | A fix MR, or a finding naming the commit that broke it | The failing job passes; `git bisect` agrees on the commit | near |
| 3 | **Flaky test triage** | Schedule: the archive shows a test that passed and failed on the same code | Run logs and CI history for that test | A fix, or a quarantine MR with the evidence | The test passes N times in a row in a clean worktree | near |
| 4 | **Characterization backlog** | Schedule: an untested module ranked by change frequency (git history) | The module's code and history, real payloads where they exist | A maintenance mission's MR: tests pinning today's behavior | Tests green on the base; a mutation score above a set threshold | near |
| 5 | **Incident to reproduction** | Alert, through the SRE agent and its knowledge base (P6) | The alert, sample events, the release in production, the KBA | An incident issue with a failing reproduction test, then a fix MR | The reproduction fails before and passes after; the alert clears in staging | near (always: production) |
| 6 | **Audit findings to fix missions** | A new audit report (an audit agent or a person) | The report's `file:line` claims and the code | Each finding turned into a test on today's code (verification by execution, ideas.md); confirmed ones become issues | The test demonstrates the behavior; a human labels it intended or a bug | near |
| 7 | **Spec drift** | Schedule, or a merge to the target branch | Specs, contracts with assertion IDs, tests, `decisions.tsv` | A finding or a doc MR when code and spec disagree (P17's drift check, run on a schedule) | Every assertion ID has a test that names it | out for the report, near for any MR |
| 8 | **The factory improves itself** | Schedule (weekly) | The run archive, scores, journals across missions | A PR on the factory with a before-and-after benchmark (P15) | The benchmark, on the targeted cases and a control suite | near (a human merges every factory change) |
| 9 | **Onboarding a new project** | A new repository joins the team's group | Its manifests, CI file, install scripts | `factory setup`'s report and an onboarding MR (D102) | Setup's rehearsal: green twice, red with a planted failing test | near |

Not candidates, on purpose: feature work (the contract needs a person), anything that deploys, and anything that changes the guards or the gates (P15's forbidden list).

## Worked use case: the 3:46 AM incident

Candidate 5 in full, with an SRE agent that reads the observability platform's traffic (problems, traces, logs, deployment events) and never writes to production.

**Detection is code first; a model is optional.** Classifying traffic must stay predictable and keep working when no model is reachable. Four tiers, each one only sees what the previous one couldn't decide:

1. **Rules:** status codes (5xx is an error, 4xx is the caller's), timeouts, known exception types, health checks. Deterministic, free, instant.
2. **Known signatures:** an error message turned into a template (variables replaced: ids, numbers, paths; the Drain algorithm does this for logs) and matched against the KBA's signatures. A new template is itself a signal.
3. **Rates against a baseline:** a signature's rate compared with its usual level (a moving average and a threshold, or the platform's own anomaly detection, which already does this: its problems are a better trigger than raw lines).
4. **A model, optional:** only for what is left (a new signature with no rule), using a model the gateway already serves. If it is unavailable or too slow, the row goes to a "suspicious" list for the morning, and nothing else changes.

The model's real place is later, in investigation and root cause, where reasoning over evidence is the job.

**The engineer near the loop classifies too, and each answer becomes code.** Two kinds of human touch, both near the loop: approving a fix, and labeling an event the tiers couldn't decide ("known, harmless", "a new incident", "belongs to another team"). A label is not just feedback for a model: it becomes a rule or a signature in the KBA, with the event that produced it as its example, so the same case is decided by code next time. The share of events reaching tier 4 should fall week after week; if it doesn't, the labels aren't turning into rules. A confidence shown on every row means something only if it is calibrated against those labels; a classifier that says 1.00 on everything says nothing.

**3:46 AM, out of the loop: the agent works.**

1. **Detect.** The platform raises a problem (a webhook from its problem notifications), or the tiers above flag a signature. The agent deduplicates it against open incidents, checks a severity threshold, and matches it against the knowledge base (KBA). Known problem with a runbook: it posts the runbook steps for the on-call (or NOC) team and stops; runbook actions on production stay human. Unknown, or a known one whose runbook points to code: it continues.
2. **Investigate.** Read-only: the failing requests' traces, the logs around the first occurrence, the affected services and their dependencies, error rate against its baseline, and the deployment events (which release went out, when). It writes an incident issue (P16) with this evidence, redacted, and labels it `factory:incident`.
3. **Root cause.** The intake (one door) opens an incident mission. The factory's investigator (D99, P13 when the cause may be in another service) takes the commit range between the last good release and the current one, forms hypotheses with evidence, and asks the explorers for detail. Its conclusion names where the fix belongs: here, another team's repo (a finding for them), or configuration (a finding for the on-call).
4. **Reproduce, then fix.** From a captured failing request (scrubbed into a fixture), a test that fails on today's code for the stated reason; then the fix, through the usual gates: test on base (red, then green), lint, the frozen characterization tests, review by another family.
5. **Ready for review.** The MR is open, the issue holds the timeline, the evidence, the reproduction and the fix, and the on-call is notified through the forge.

**7:00 AM, near the loop: the human decides.** The engineer reads one issue: what happened, why, the test that proves it, the fix. They approve, or redirect with one comment. The merge and the deployment go through the team's own pipeline and its approvals: the factory never deploys.

**What, other than the agent or the engineer, shows it was right:**
- the reproduction test fails before the fix and passes after;
- replaying the captured failing requests against staging no longer produces the error signature;
- after the release, the platform's own error rate for that service returns to its baseline, and the problem closes. The observability platform is the outside judge, which is what makes this candidate worth the effort.

**Data it produces:** time from first occurrence to ready-for-review, against today's time to resolution; hypotheses ruled out per incident; how often the KBA match was right; how often the fix belonged elsewhere.

**Risks, and what holds them:**
- **Logs are untrusted input.** Anyone who can make the service log a line can write text the agent reads (prompt injection). The agent treats log and payload content as data, never as instructions; it has no tool that writes to production; the factory's guards and gates apply to anything it proposes.
- **Personal and secret data in traffic.** Fixtures and evidence go through redaction before they reach an issue or a repo; payloads are minimized to the fields the reproduction needs.
- **Alert storms.** Deduplication, one incident mission per problem, a cap per night, and quiet hours for low severities.
- **A wrong root cause at 4 AM.** Nothing ships without the 7 AM review; the reproduction test and the staging replay are what the reviewer checks first.

**First step, with no risk at all:** a daily digest. The SRE agent reads the last 24 hours of problems and writes, for each one, its classification (known or not, which KBA, which release, a suspected service), without opening anything. For two weeks the on-call team marks each line right or wrong. That accuracy decides whether step 2 may open issues on its own, and it doubles as the status chatbot's first content for the NOC team.

## The order

1. **Make the engine durable and reachable** (P12, P16): a mission waits at a gate without a terminal, and the gate is answered from the forge. Nothing above starts before this.
2. **Candidate 1, then 2.** Their outcomes are decided by tests and scanners, they are small, and they produce many short runs: the fastest data on unattended work.
3. **Candidates 3 and 4.** They feed the archive and the benchmark with real cases.
4. **Candidates 5 to 9**, each when its own prerequisites exist (the SRE agent, an audit agent, P17, P15).

Each candidate starts near the loop. It moves out of the loop for one class of change only (for example, patch-version bumps) after its own record shows the gates caught everything a human reviewer would have: a number of consecutive MRs merged unchanged, chosen per lane.

## How we'll know it works

Not by the number of agents running. By, per candidate:

- MRs merged without a human change, and the share reverted later;
- human minutes per MR, from `decisions.tsv` and the forge's timestamps;
- for the "out" lanes, the count of runs a human never had to open.

## Trade-offs

| For | Against |
|---|---|
| Work starts on events, not on a person being free | A wrong engine multiplies its mistakes: hence the entry criteria |
| Each lane is chosen by how much code, not a model, decides its outcome | Many small MRs can flood reviewers: a cap per lane per day |
| The data flywheel (P14, P15) gets real cases every day | Always-on runs need a shared runner with its own credentials and quotas (P6, P1), and the sandbox is still rule-level until then |

## What it borrows

- The October 2026 talk on near-loop and out-of-loop agentic engineering: triggers, one API, a durable agent in a sandbox; "work happens before and after you check in"; measure by useful agents working while you're away.
- Our own proposals: P4 (one door, a director), P6 (labeled issues, the SRE agent), P12 (durable runner), P15 (self-improvement), P16 (gates on the forge), P17 (drift), D102 (setup).
