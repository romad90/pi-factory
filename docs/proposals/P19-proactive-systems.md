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
