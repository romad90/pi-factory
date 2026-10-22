# P5. Continuous improvement: observe, decide, improve, prove

**Status:** draft · **Effort:** L · **Depends on:** P3 (frozen behavior), P4 (scheduled runs) for the unattended part

## Problem

A team wants its agents to make the codebase better over time: not a lint sweep, but steady attention to where the code makes work hard, and a habit of fixing it a little at a time.

Telling an agent to "always improve the code" doesn't produce that:

- **Agents don't remember.** Each run starts fresh and ends with its ticket. What a worker noticed about a module is gone when its run ends, so nothing accumulates.
- **Unscoped initiative is scope creep.** In mission 2, a worker on the harness ticket also wrote the glossary and the modes document, which belonged to another ticket. Initiative without a frame produces diffs nobody asked for, and review rejects them.
- **Mechanical improvement goes where the counts are, not where the work is.** A lint or complexity count says nothing about which module the team changes every week, which one caused the last two hotfixes, or which one costs an extra round in every mission.

The long-term drive has to live in the factory, not in a prompt: in what agents record, in what is measured, and in who sets the direction.

## Proposal

Four parts, each usable on its own, together a loop.

### 1. Observe: every run leaves notes

Every worker, reviewer and steward report gets an **Observations** section: friction met while doing the ticket, with `file:line` and evidence. Examples: "three modules to change to add one mode", "this function is untestable without a real database", "this branch is duplicated in every mode handler".

- An observation is **never acted on in the ticket**. It is recorded, the ticket stays in scope.
- `collect.sh` appends observations to a per-repo **codebase journal** (`docs/factory/journal.md`), deduplicated by location. The journal is the memory the agents don't have.

**Patterns become rules.** Factory's Missions learn skills from repeated work (observe, learn, encode). Ours is the retro's "three times, automate", run by the factory: when the same pattern appears in three round journals (D84), three decisions in `decisions.tsv` or three findings, the strategist proposes the rule it suggests (a resolver rule, a brief line, a ticket-writer check) with the three pieces of evidence. The human accepts or rejects it like any proposal; nothing changes on its own.

### 2. Decide: a strategist proposes, the human chooses

A strategist run (the code steward's role extended, or its own agent from the judges' family) reads:

- the journal,
- the health trend (`.factory/health-baseline.json` over time),
- the git history: **hot spots**, the files that change often and are complex, and the files touched by hotfixes and reverts,
- the repo's **north star**: a short architecture-vision document the team writes and owns (target structure, standards, what to avoid), and the ADRs and `GLOSSARY.md`.

It uses the **improve-codebase-architecture** skill for the method, which already weighs recent change history, uses the `codebase-design` vocabulary (module, interface, depth, seam, locality, leverage), applies the deletion test and respects ADRs. One adaptation: in the factory the skill runs without the interactive part. It writes its candidate report (HTML, with before/after diagrams and a recommendation strength per candidate) to the mission folder, and stops. The grilling loop happens with the human, when one is picked.

Output: **at most three candidates**, each argued in terms of the team's work ("this module changed 14 times in six months, two hotfixes, every mission touching it needed an extra round"), with its distance to the north star.

The human picks one, rejects one with a reason (which becomes an ADR so it isn't proposed again, as the skill already offers), or does nothing.

### 3. Improve: an improvement mission ends in a pull request

A picked candidate becomes a mission of intent `improve`. It runs the normal lanes with stricter gates:

| Gate | Rule |
|---|---|
| Scope | Only code already covered by frozen tests (P3). No characterization test may change: a diff to one fails the patch guard. |
| Proof | The mutation score on the touched files must not drop, and the health baseline must improve. |
| Size | A cap on files and lines changed. A candidate too big for it is split by the ticket writer, or sent back. |
| Review | The usual review and steward gates, plus the steward checks the diff against the candidate it was approved for. |

When every gate passes, the factory **opens a pull request** (draft by default) labeled as an improvement, with the candidate card, the gate results, the mutation score before and after, and the observations it closes.

**It never merges.** Merging stays with the team's normal review. That keeps the human at the one point where judgment matters most, and costs little: the PR arrives with its evidence.

### 4. Prove: the retro checks the return

Each improvement records what it predicted ("fewer rounds on this module", "this test becomes possible"). The retro compares with what happened over the following missions: rounds per ticket on the module, hotfixes, time to change. The strategist reads those results next time. Improvements that don't pay off lower the weight of that kind of candidate.

### Budget and pace

- **One open improvement PR per repo** at a time. A second waits until the first is merged or closed. This is the brake on review load.
- **A small share of each mission** (proposed: one ticket in ten) may be an approved improvement on code the mission already touches.
- **Unattended runs (with P4):** the strategist on a schedule, improvement missions started only from candidates a human picked. The schedule never picks for itself.

### Autonomy levels, switched on in order

| Level | What runs alone | Human step |
|---|---|---|
| 0 | Observations and journal | none |
| 1 | Strategist report | pick a candidate |
| 2 | Improvement mission up to a draft PR | review and merge |
| 3 | Small `Strong` candidates within the size cap start without a pick | review and merge |

Level 3 only after level 2 has held for several PRs, measured in the retro.

## Trade-offs

| For | Against |
|---|---|
| Improvement becomes steady and visible instead of a yearly cleanup | More decisions for the human. Mitigation: at most three candidates, one open PR, argued in the team's terms |
| Effort goes where the team works (hot spots), not where the counts are | Hot spots need history; a young repo or a big squash merge hides them. The strategist falls back to the journal |
| The journal turns many small runs into one memory | The journal can grow into noise. Deduplicate by location, and expire entries the code no longer matches |
| Every PR carries its proof (frozen tests unchanged, mutation score, health) | Depends on P3: no improvement mission on code without frozen tests. On a legacy repo, characterization comes first |
| The north star keeps the strategist on the team's direction, not its own taste | Someone has to write and keep the north star. Without it, the strategist only reduces friction locally |

**Branch names and pipelines.** An improvement branch must not trigger the team's deploy rules (some repos publish branches by prefix). The branch prefix is a setting in `commands.env`, checked against the repo's CI rules at install.

**Rejected alternative:** a prompt line asking every agent to improve what it touches. It produces unreviewable diffs and scope creep, and nothing measures whether it helped.

## What it unlocks

- **The maintenance lane's last step.** P3 understands and freezes; P5 improves, under that protection, continuously.
- **A measured debt backlog** the team can read: the journal and the candidate reports, with the cost of each item in rounds and hotfixes.
- **With P4:** a repo that gets better between human missions, at a pace the team sets.

## Perspective

The obsession the team wants is not a personality the agents have; it's a loop the factory runs. Notice everything, act on little, argue each change in the team's terms, prove it, and learn which kinds of change pay. Over months the journal and the retro results become the team's own map of where its code hurts and what fixing it is worth.

## Plan

1. Observations section in worker, reviewer and steward reports; `collect.sh` appends to the journal with deduplication. **S**
2. North-star template (`docs/factory/north-star.md`) and its place in the steward's brief. **S**
3. Strategist step: `workflow.sh strategist`, running improve-codebase-architecture non-interactively, at most three candidates, report in the mission folder. **M**
4. Intent `improve`: gates (frozen tests unchanged, mutation score, health ratchet, size cap), then a draft PR through the existing `pr` skill. **M**
5. Retro: predictions vs results per improvement; fed back to the strategist. **S**

## Open questions

- Is the strategist the code steward with a second mode, or its own agent? Proposed: its own agent, same family as the judges, so the steward stays a pure judge.
- Which history window defines a hot spot? Proposed: six months, weighted by recency.
- Should observations from the human (in review comments) go to the journal too? Proposed: yes, tagged as human.
