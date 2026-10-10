# Why this factory exists

This is the intent behind every other document. The [design guide](DESIGN.md) says how the factory works, the [ladder](LADDER.md) says where it stands, the [roadmap](ROADMAP.md) says what comes next. This page says what all of it is for, and how we will know whether it worked.

## The goal: shift the work, not the volume

Writing code faster is not the goal. The goal is the day correction and maintenance run by themselves in the background, and the team spends its time on things that were never in scope before: not the same work faster, different work.

Value comes from what the team can now reach, not from how many lines an agent produced.

## What we refuse: fast code, slow review

Agents can write in three days what then takes three days to review. That is the trap the DORA 2025 report describes: more output from AI, with the cost moved downstream to review and stability. Volume without verification doesn't remove human work, it moves it to the most expensive place: a senior engineer reading generated code line by line.

So the order is fixed:

1. **Self-verification first.** Agents must prove their own work: a contract written before the code, judges from another model family, behavior checked against hidden cases, code health measured and judged, every claim backed by evidence or labelled UNVERIFIED.
2. **Better models second.** A better model inside a loop that can't verify itself only produces more to review. A model of today inside a loop that verifies itself already moves work off the team.

This is the condition for Step 3 on the [ladder](LADDER.md): humans supervise outcomes and exceptions, not steps. Without trusted self-verification, there is no Step 3, whatever the model.

## How we measure the gain

**Not the token price.** What counts is the cost of an accepted result: tokens and requests per change that merged and stayed merged.

**The real denominator is human time.** The return on the factory is:

```
gain  = human hours the work would have cost by hand (build + review + rework + maintenance)
cost  = human hours spent on the mission (spec, decisions, spot checks, MR review)
      + model spend
      + engineering hours put into the factory itself
ROI   = gain − cost, per mission and over time
```

Per mission, we record:

| Measure | Why |
|---|---|
| Estimated manual effort, written before the mission | The baseline. Estimated by the team as they would for a normal ticket, before the factory runs, so it can't be bent afterwards. |
| Human minutes spent, by kind (spec, decisions, spot checks, MR review) | The cost that matters. If review time stays as long as build time, the factory has only moved the work. |
| MR review time | The direct test of "three days to write, three days to review". |
| Rework after merge (escaped bugs, reverts, follow-up fixes) | A fast merge that comes back isn't a gain. |
| Share of maintenance done in background | The goal itself. Zero today: the maintenance lane doesn't exist yet. |

These go in the [evidence log](LADDER.md#evidence-log). Until the factory computes them (roadmap H1), they are recorded by hand from `decisions.tsv` timestamps and the MR.

## How much to invest in the factory itself

The factory is engineering work too, and it counts as cost. The rule:

- **Invest in verification when it removes measured human time.** Every factory change names the human step it removes or shortens, and the next mission checks that it did.
- **Don't invest ahead of evidence.** A dashboard that shows progress is not a feedback loop. Supervision tools come after the measures they display exist.
- **Stop when the loop is trusted enough for the work at hand.** The bar is not perfection. It is: an MR approved from verdicts and metrics, with spot checks only, and no surprise after merge.

## Where the trust loop stands, end to end

Can the factory verify and attest a change from spec to merge, and after it? Not yet completely. The chain, link by link:

| Link | Verified by | Status |
|---|---|---|
| Spec → definition of done | Contract, critic from another family, your approval | ✅, ⚠️ a contract can contradict itself and pass (C6) |
| Definition of done → tickets | Ticket writer, coverage check (G2), your approval | ✅ |
| Ticket → code | TDD worker, patch guard, integration gate (lint, tests, extra check) | ✅ |
| Code → assertions | Fresh reviewer from another family, rounds counted by script | ✅ |
| Feature → behavior | Validator on hidden cases | ⚠️ no harness: behavior still relies on human acceptance (X1) |
| Mission → codebase health | Ratchet + code steward (G5) | ✅ |
| Spec, contract, code, docs agree at merge | Drift check | ❌ (C10) |
| Evidence a reviewer reads in a minute | READY report | ❌ (S3) |
| The judges themselves | Skill evals, pass@k | ❌ (X2) |
| After merge: correction and maintenance | Maintenance lane, triggered missions | ❌ (X9, after Step 2): the goal itself |

The two holes that block "attest end to end" are behavior (X1) and the judges' own reliability (X2). The hole that blocks the goal is the maintenance lane (X9).
