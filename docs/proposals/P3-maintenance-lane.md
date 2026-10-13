# P3. Maintenance lane: discover, confirm, freeze, refactor

**Status:** draft · **Effort:** L · **Depends on:** P1 (throughput)

## Problem

The goal of a maintenance mission is to align a legacy system with the team's ability to change it safely. The factory has to learn the domain, the purpose, the dependencies and the battle-tested behavior from the code, freeze the current behavior as the truth, then refactor and bring the code to the team's standards without breaking anything.

Mission 2 used the feature path for that, and the feature path asks the human the wrong questions:

- **The interview asked a person to explain code the code could explain.** About 1h30 of questions, many answerable by reading `src/` (layout, branches, inputs). The human spent hours steering the session toward the right questions.
- **The contract asked a judge to decide what only running the code can decide.** Three contract rounds; one author invented behavior from the team's target rules (`BotExecutionResult`, exit codes 2–4) that the code doesn't produce. Asking the author for literal values cost 28 minutes and 2.6M tokens.
- **Nothing proved the tests actually freeze the behavior.** A characterization test that asserts too little passes review and protects nothing. A reviewer can't see that.

## Proposal

A lane of its own, with four phases. The human confirms; agents and tools do the rest.

### 1. Discover (agents, no human)

A discovery run produces a **system dossier** in `.scratch/<mission>/dossier/`. Every claim carries its source (`file:line`, commit) and a confidence level.

- **Static map:** entry points, modes, branches per mode, external I/O (collections read and written, HTTP endpoints, environment variables, exit paths), dependency graph. Mostly tools (AST, grep, the type checker), with one agent writing it up.
- **History:** `git log` and `blame` on the risky areas. Hotfixes, reverts and commit messages say *why* a piece of code exists. That's the battle-tested knowledge the refactor must keep.
- **Gaps against the team's standards** (AGENTS.md, engineering rules), each with `file:line`.
- **Suspected bugs** (a `return` in a `finally`, a success log after a failure, dead code).
- **Drafts** of `GLOSSARY.md` and `docs/modes.md`.

### 2. Confirm (human, short)

Instead of an open interview, a **questionnaire ranked by uncertainty**. Only the low-confidence claims, each phrased to be answered yes, no, or with one line:

> Mode X calls nothing but logs "Not Implemented Yet" (`worker.ts:57`); `syncModeXInfrastructures` is unreachable. Dead code, or planned? **yes / no / note**

The answers go to `decisions.tsv`. The dossier becomes the spec. The human time target is under an hour for a worker the size of mission 2's.

### 3. Freeze (tools, then a mechanical gate)

- **Tests are recorded, not written from a contract.** Workers build the harness and the scenarios from the dossier (one per branch and I/O path). The expected values come from **running the current code** (golden master / approval tests). The contract lists *which* behaviors are frozen, never their literal values.
- **The G4 gate becomes mutation testing.** A mutation tool (Stryker for JS/TS, mutmut for Python, PIT for the JVM) changes `src/` in small ways. Each surviving mutant is a behavior the tests don't freeze, reported with its `file:line`. The gate passes when the mutation score on the touched code reaches the bar the team sets (proposed: 80% to start, ratcheted up).
- Survivors become tickets, not judgments.

### 4. Refactor and align (under frozen tests)

- The refactor mission (2b) runs with the frozen tests **unchanged**: any diff to a characterization test fails the patch guard.
- The standards gaps from the dossier become small tickets, one gap each. A **ratchet** counts them: the number can only go down.
- Suspected bugs are triaged by a human into fix tickets (a later bugfix mission) or accepted behavior.

## Trade-offs

| For | Against |
|---|---|
| Human time moves from explaining to confirming: from hours to under an hour | Discovery costs tokens up front, on every legacy component, before any value is visible |
| Mutation testing is objective: it proves the tests freeze behavior, which no reviewer can | Mutation runs are slow (minutes to hours on a large codebase). Scope it to the files the mission touches, run it once per mission, not per ticket |
| Golden-master values come from the code, so nobody can invent behavior | Golden masters freeze bugs too. That's intended (current behavior is the truth), but it must be visible: every frozen bug is listed in the dossier and in the MR |
| The dossier is lasting documentation for the team, not a by-product | Non-deterministic outputs (timestamps, ordering, random IDs) need scrubbers in the harness. One more thing for the harness ticket |
| Standards alignment becomes measurable (the gap count) | Needs a mutation tool per language: a pack concern (`packs/<lang>`) |

**Rejected alternative:** keep the feature path and add maintenance rules to the contract author's prompt. Mission 2 tried that: the author still imported the target rules, and nothing checked the result.

## What it unlocks

- **Mission 2b (refactor) becomes safe by construction:** the frozen tests plus the mutation score are the proof, readable by a reviewer in a minute.
- **Mission 3 (standards alignment, new sync) starts from a measured gap list,** not a rereading of the code.
- **Onboarding:** the dossier is what a new engineer reads first.
- **The maintenance lane (X9)** that [INTENT.md](../INTENT.md) names as the goal itself. With P4, discovery can run on a schedule across a team's legacy components and keep each dossier current.

## Perspective

Legacy work is where agents can return the most human time: reading old code is slow and unrewarding for people, and the risk is controlled once behavior is frozen and proven frozen. The order matters: understand, prove, then change. Over time each component carries its dossier and its mutation score, and a team can see which parts of its system are safe to change and which aren't, as a number rather than an opinion.

## Plan

1. `maintenance` pack: dossier format, questionnaire format, discovery agent and its brief. **M**
2. `workflow.sh discover`, and the questionnaire step in `next.sh` (`STEP: confirm`). **M**
3. Golden-master harness guidance and scrubbers in the pack; contract format for "frozen behaviors" without literal values. **S**
4. Mutation gate: `FACTORY_MUTATION_CMD` in `commands.env`, scoped to touched files; G4 for `Intent: maintenance`. **M**
5. Standards ratchet: gap count in `.factory/health-baseline.json`. **S**

## Open questions

- Which mutation score is realistic as a first bar on legacy code? Proposed: measure on mission 2 before fixing a number.
- Should discovery read the issue tracker and incident history too, when a connector exists? It's where much of the "why" lives.
- Who owns the dossier after the mission: committed in the repo under `docs/`, or regenerated on demand?
