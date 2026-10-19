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

Smaller ideas seen in other tools, not yet proposals, are collected in [ideas to borrow](ideas.md).
