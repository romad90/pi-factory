---
name: mission-retro
description: The factory's retro of a mission, built from the mission's whole record (every session, not only this one) and kept private. Use at STEP pr, after the MR is open, or when the human says retro for a mission.
---

# Mission retro (factory)

The method is the `retro` skill: read its `SKILL.md` for the categories (navigation, automated checks, coding standards, tool economy, information access) and the rule that a mechanical violation gets a check, not a sentence. This skill adds what a factory mission needs.

## 1. Read the record, not your memory

Run `scripts/factory/retro.sh pack <mission>` and read all of it. It holds what every session left behind: metrics, verdicts and rounds per ticket, the human's decisions, amendments and withdrawals, pauses and provider errors, guard refusals, request sizes. This session may have seen only the end of the mission; the pack saw all of it. Open the files it points to (journals, verdicts, decisions) when a line needs its detail.

A finding needs evidence from the pack or a file it names: a decision's date and text, a round count, a refusal rule, a token figure. A finding you remember but can't point to in the record is left out.

## 2. Look for these, in this order

- **Cost**: tickets with many rounds or turns, the largest requests, tokens spent on work that produced nothing.
- **Human interventions**: every row of decisions.tsv is a place the factory could not decide. Which could a rule, a check or a better brief have settled?
- **Gate and format failures**: verdicts sent back, coverage or validate steps that stalled, guard refusals that stopped legitimate work.
- **Environment**: provider limits (429), setup or onboarding gaps, wrong commands.

## 3. Write `.scratch/<mission>/retro.md`

```markdown
# Retro: <mission>

<two lines: what the mission did, its intent>

| # | Finding | Evidence (from the record) | Fix | P | Kind |
|---|---|---|---|---|---|

## Result
<the metrics line: tickets, rounds, first pass, decisions (target 5), runs, tokens, cycle time>
```

P1 blocks or wastes a lot, P2 friction, P3 nice to have. Kind is one of: cost, intervention, gate, guard, environment, setup, docs. Name factory scripts, steps and agents freely; the retro stays private. Keep findings general enough to recur on another project: say "a ticket whose deliverable is outside the patchable tree", not only the ticket's name.

## 4. Save it, then stop

Run `scripts/factory/retro.sh save <mission>`. It copies the retro to this machine's data folder, outside every repository, where `factory learn` reads every project's retros. Never write a retro into the factory's own folder: it mirrors a public repository. Then show the human the findings table, and stop.
