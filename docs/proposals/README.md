# Proposals

Changes too large to decide in a pull request. Each proposal states the problem with its evidence, what it would build, what it costs, what it unlocks, and what is left open. A proposal becomes ADR decisions and roadmap items once accepted; until then it changes nothing.

Status: **draft** (open for discussion) · **accepted** (in the roadmap) · **rejected** (kept, with the reason).

| # | Proposal | Status | Depends on |
|---|---|---|---|
| P1 | [Several gateways, fallback chain, production budget](P1-gateways.md) | draft | — |
| P2 | [The lead becomes a script](P2-scripted-lead.md) | draft | — |
| P3 | [Maintenance lane: discover, confirm, freeze, refactor](P3-maintenance-lane.md) | draft | P1 |
| P4 | [Director and triggers](P4-director.md) | draft | P1, P2 |
| P5 | [Continuous improvement: observe, decide, improve, prove](P5-continuous-improvement.md) | draft | P3, P4 |
| P6 | [Control room: a hosted factory, a dashboard, events from operations](P6-control-room.md) | draft | P2, P4, P5 |
| P7 | [Launch gate: done when the service runs, in a sandbox, secure by design](P7-launch-gate.md) | draft | — |
| P8 | [Hands-off mission: the human decides, the factory does the rest](P8-hands-off-mission.md) | steps 1–3 done | P2 for the last step |
| P9 | [Rounds that converge: reproduce first, carry what was learned, doubt the contract early](P9-converging-rounds.md) | draft | — |
| P10 | [Front page: every subagent, at every stage, on one page](P10-front-page.md) | draft | — (P2 completes the events) |
| P11 | [Install the factory once per machine; onboard a project with only what is its own](P11-install-once.md) | draft | — |
| P12 | [A durable runner: the mission survives a closed laptop, and the human answers from anywhere](P12-durable-run.md) | draft | P2 |
| P13 | [Context repos: investigate across services, change only one](P13-context-repos.md) | draft | — |
| P14 | [Measure and improve: a run archive, a benchmark from our own tickets, scoring](P14-measure-and-improve.md) | draft | — (P5 builds on it) |
| P15 | [The factory improves itself: agents that read failed runs and propose changes to the factory](P15-factory-improves-itself.md) | draft, later | P14 |
| P16 | [Issue in, MR out: the factory works where the team already looks](P16-issue-in-mr-out.md) | draft, after mission 4 | P2 (P12 keeps it running) |
| P17 | [Plans that leave no decision: readiness, reuse, plain words, drift](P17-plans-that-leave-no-decision.md) | draft, after mission 4 | D94, P14 |
| P18 | [Setup by rehearsal: the factory finds its own commands and proves them as a worker would](P18-setup-by-rehearsal.md) | accepted (D102) | P11 |
| P19 | [Proactive systems: work that starts before anyone sits down](P19-proactive-systems.md) | draft, later (entry criteria) | P12, P16, P14, P4 |
| P20 | [Token budget: every agent fits a known budget, measured before it is cut](P20-token-budget.md) | proposed; step 1 built (`factory tokens`) | D97, D85 |
| P21 | [Security layer: a scanner gate in code, then a security axis that reads what the scanner can't](P21-security-layer.md) | proposed, after mission 5 | D62, P20 |
| P22 | [One entry, derived process: the change sets the tier, a function in code sets the steps](P22-one-entry-derived-process.md) | proposed, after mission 5 | lanes, P20, P21 |

## Why these four, in this order

Mission 2 ([retro](../retros/mission-02.md)) spent about four hours of human time on the mission itself and about six on the infrastructure around it. The four proposals answer the four things it taught:

1. **The gateway is part of the system.** One shared key, one quota per model, models that behave differently under tool calls. Every wave failure came from there (P1).
2. **An LLM is the wrong tool for a deterministic loop.** The lead's job is to follow `next.sh`. Each time it improvised, it cost a round or a commit to undo (P2).
3. **Maintenance asks the human the wrong question.** The interview asked a person to explain code the code could explain itself, and the contract asked a judge to decide what only running the code can decide (P3).
4. **Missions should start without a person typing `/factory`.** That is the goal in [INTENT.md](../INTENT.md): maintenance running in the background. It needs 1 and 2 to hold first (P4).

P1 and P2 are prerequisites, not features: they make the factory dependable. P3 and P4 are where the return is.

P5 came after: it answers how the codebase gets better over time once the factory can change it safely (P3) and run on its own (P4). P6 puts the whole factory where a team can watch it, and plugs in operations: alerts from an SRE agent and labeled issues become missions.

P7 changes what "done" means: a mission ends when the service builds and boots with its real configuration, in a sandbox, not when the tests pass.

P8 comes from counting what the human did in mission 2: most of it was plumbing, rules the worker didn't have and hand repairs, not decisions. Its target is at most five human interventions per mission, and it comes first.

P9 comes from the end of mission 2: 4 of 10 tickets escalated after three rounds, while others passed on round 1. Rounds started almost from scratch, fixes were written before the failure was reproduced, and one wrong line in the contract surfaced as failures in several tickets.

P10 answers what the human did most during mission 2 besides deciding: finding out what was going on. The files already know; a read-only local page shows it, and P6 later hosts the same page.

The [assessment after mission 2](assessment-2026-10.md) sorts all of them and the borrowed ideas by what that mission showed.

P11 comes from mission 3's first day: a pulled branch brought another machine's models, two machines ran two factory versions, and every release was a 25-file diff in the project. The factory belongs to the machine; a project keeps what is its own.

Smaller ideas seen in other tools, not yet proposals, are collected in [ideas to borrow](ideas.md).

P12 answers P2's open question with Pi Durable, a library from Pi's authors that saves every step before running it: the mission keeps running when the laptop closes, questions wait as approvals any client can answer, and the cockpit gets a live feed. The files stay the source of truth, so the factory still works without it.

P13 comes from a bug between an API and the two bots that keep it in sync. One mission still changes one repo; the others become read-only context, mapped by one fresh agent per repo, and an investigation step finds the cause and reproduces it in the repo being fixed before any contract is written.

P14 makes the factory measurable: keep every run, replay real tickets as a benchmark across models and factory versions, score runs for failure modes tests cannot see, and aggregate cost per merged MR across missions. It is what lets P5 prove an improvement before it is merged, and what gives the pilot its numbers.

P15 is P5 one level up: agents that read the run archive and scores across missions, find failure patterns seen at least three times, propose the smallest change to the factory, prove it with a before-and-after benchmark, and open a PR a human merges. The safety layer is out of their reach.

P16 takes the experience Warp Factories sells, issue in and reviewed MR out, without its hosted product: a labeled issue starts a mission, the factory comments on it only at human steps, and approvals come back as comments from listed humans, checked by the forge's identity, which closes the self-approval hole D101 left open.

P17 takes four checks from Google's Elephant-Goldfish Model into roles we already have: a design that leaves the worker no decision, a code search before anything new is built, every term defined, and a drift check before the MR. Each one is kept only if the next missions' numbers show it helps.

P18 comes from onboarding mission 4's project: ten problems found by hand at a red prompt, every one readable or testable by a script. Setup reads the project's CI file and manifests for its commands, rehearses them under a worker's conditions (fresh worktree, offline, no credentials, guard on), checks the machine and the gateway the same way, and hands the human one page to approve.

P19 lists what to make proactive once the engine is efficient: triggers, one intake, a durable runner in a sandbox. Nine candidates are ranked by how much code, not a model, decides their outcome, starting with dependency bumps and a red main branch. Entry criteria from measured missions decide when the first one may start, and each lane leaves the loop only on its own record.

P20 makes scarce tokens a design rule. A mission stopped because one reviewer request was over a key's 45,000-token limit: every agent turn resends its whole conversation. Step 1, `factory tokens`, shows each run's request sizes and the tool results that fill them; the next steps (capped tool output, briefs that send only what the job needs, a hard budget per request, fewer agents rereading the same diff) are each kept only if the numbers move.

P21 adds the security review the factory doesn't have. A scanner (Semgrep, rules pinned, offline) gates every mission's diff with a ratchet like lint: no new findings. Dependencies the mission adds or upgrades are audited. When the diff crosses a boundary (input, auth, outside calls, files, queries), a fresh security axis on another family traces untrusted values to their sinks and checks authorization, reading only the diff and the scanner's findings. A seeded benchmark measures recall and false alarms before any of it gates.

P22 replaces the three lanes with one entry. The person describes the work; a function in code derives the tier from the change (paths, boundaries, size, intent) twice: predicted at intake to plan the steps, actual from the diff before the MR, which can only escalate. Each mission writes its plan and why; the tier sets the steps and, through the forge, the approvals (one for low and medium, two for high). Auto-merge for low comes only after evidence, with a revert-rate circuit breaker. A shadow phase compares the function with the person's choices first.
