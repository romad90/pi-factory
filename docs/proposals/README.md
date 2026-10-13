# Proposals

Changes too large to decide in a pull request. Each proposal states the problem with its evidence, what it would build, what it costs, what it unlocks, and what is left open. A proposal becomes ADR decisions and roadmap items once accepted; until then it changes nothing.

Status: **draft** (open for discussion) · **accepted** (in the roadmap) · **rejected** (kept, with the reason).

| # | Proposal | Status | Depends on |
|---|---|---|---|
| P1 | [Several gateways, fallback chain, production budget](P1-gateways.md) | draft | — |
| P2 | [The lead becomes a script](P2-scripted-lead.md) | draft | — |
| P3 | [Maintenance lane: discover, confirm, freeze, refactor](P3-maintenance-lane.md) | draft | P1 |
| P4 | [Director and triggers](P4-director.md) | draft | P1, P2 |

## Why these four, in this order

Mission 2 ([retro](../retros/mission-02.md)) spent about four hours of human time on the mission itself and about six on the infrastructure around it. The four proposals answer the four things it taught:

1. **The gateway is part of the system.** One shared key, one quota per model, models that behave differently under tool calls. Every wave failure came from there (P1).
2. **An LLM is the wrong tool for a deterministic loop.** The lead's job is to follow `next.sh`. Each time it improvised, it cost a round or a commit to undo (P2).
3. **Maintenance asks the human the wrong question.** The interview asked a person to explain code the code could explain itself, and the contract asked a judge to decide what only running the code can decide (P3).
4. **Missions should start without a person typing `/factory`.** That is the goal in [INTENT.md](../INTENT.md): maintenance running in the background. It needs 1 and 2 to hold first (P4).

P1 and P2 are prerequisites, not features: they make the factory dependable. P3 and P4 are where the return is.
