# P15. The factory improves itself: agents that read failed runs and propose changes to the factory

**Status:** draft, for later · **Effort:** M · **Depends on:** P14 (run archive, scoring, benchmark); P5 shares its strategist

## Problem

Every improvement to the factory so far came from a person reading a mission after the fact: 85 decisions in the ADR, 70+ retro findings, each found by hand. It works, and it is slow, and it depends on someone noticing. Mission 3 went from 31 human decisions to 4 because of fixes written between missions; the next ten missions should not need a person to find the next fix.

P5 improves the **codebase** (friction the agents meet in the code). This proposal is the same loop one level up: it improves the **factory** (briefs, resolver rules, agents, models per role, steps, gates) from the way its own runs fail.

## Proposal

A layer of agents that works on the factory, never on a project, between missions or on a schedule.

### 1. Find patterns, with evidence

A `factory-analyst` reads, across missions and repos:
- the run archive and the scores (P14): which failure modes, on which roles and models, how often;
- the deterministic signals: failed rounds and their verdicts, patch-guard blocks, stale verdicts, no-progress escalations, questions the resolver could not answer, hand commits;
- the retros and decisions already written.

It writes `factory/patterns.md`: each pattern with its count, the missions and runs it appeared in, quoted evidence, and the factory part it points to ("reviewer asks whether to fail a missing deliverable: 7 runs, 3 missions → reviewer brief, resolver"). A pattern needs at least three occurrences in at least two missions (the "three times, automate" rule); anything rarer stays an observation.

### 2. Propose a change to the factory definition

A `factory-improver` takes one pattern at a time and drafts the smallest change that would remove it: a brief line, a resolver rule, a ticket-format rule, a model or thinking level for a role, a new deterministic check. It writes the change as a branch of the factory repo, with the pattern and its evidence as the rationale and an ADR entry draft.

### 3. Prove it before anyone reads it

The proposal runs the P14 benchmark twice, on the current factory and on the proposed one, on the cases that showed the pattern plus a fixed control suite (to catch a fix that breaks something else). The PR carries the table: pass rate, rounds, cost, and the pattern's score, before and after. No improvement on the targeted cases, or a regression on the control suite: the proposal is closed with its numbers, and the pattern stays open.

### 4. A human merges

The factory improver opens a pull request on the factory repo; it never merges, never releases, never touches a project. The human reads the evidence and decides. A merged improvement is checked again by the next missions' scores: if the pattern comes back, the analyst reopens it.

### What it may never change

The safety layer stays out of reach, by rule and by check: the patch guard, the command guard, frozen paths and frozen tests, the gates' pass conditions, secrets handling, and the human gates themselves. A proposal touching those files is refused by the factory's own CI. Making the factory more permissive is a human decision, never an optimization.

## Trade-offs

| For | Against |
|---|---|
| Improvements found by counting, not by someone noticing | Needs P14's archive and benchmark first; without them it is opinion |
| Each change arrives with measured before and after | Benchmark runs cost tokens on every proposal; run it weekly, not per mission |
| The team sees the factory get better mission after mission, with numbers for the pilot | Patterns across few missions are thin; it starts paying after about ten missions |
| The human keeps the merge and the safety layer | A model proposing changes to the harness that steers it: kept safe by the forbidden list and the benchmark, not by trust |

## What it borrows

- Warp: agents look at scored runs, find repeated problems ("seen 54 times on the triage agent") and open PRs on the factory definition.
- Google Harness²: keep a harness edit only when it changes behavior for the better on the same task.
- Factory Missions: learn skills from repeated work.
- Our own retros: the three-times rule, findings tracked to a status.

## Plan (later)

1. `factory-analyst` and `patterns.md` from the archive, scores and deterministic signals. **S**
2. `factory-improver` drafting one change per pattern on a branch, with an ADR draft. **S**
3. Before-and-after benchmark in the PR; control suite; closing rules. **M** (with P14)
4. The forbidden list enforced by the factory's CI. **S**
5. Weekly schedule; patterns that come back reopen. **S**

## Open questions

- One factory repo per team, or one per domain shared by several teams? The patterns get better with more missions; the forbidden list and the merge stay per owner.
- Should a proposal be allowed to change model choices per role on its own evidence, or are models always a human budget decision? Proposed: propose, never apply.
