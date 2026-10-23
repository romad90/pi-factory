# P13. Context repos: investigate across services, change only one

**Status:** draft · **Effort:** M · **Depends on:** nothing to start; P9 (reproduce first) fits on top

## Problem

A mission is one repo, or one project of a monorepo (D56). That is right for changing code, and wrong for understanding it when the behavior lives between services.

The case that raised it: an API whose data is kept in sync by two bots, each from its own repo, with a bug in how the three interact. The investigation and the fix needed all three repos in view; the fix itself went into one. Done by hand with another agent that held the three repos in one large context, it worked. In the factory today it can't:

| What the case needs | What the factory has |
|---|---|
| Read how the bots call the API: when, with which data, what they retry | Agents see the mission's repo only |
| Find the cause before writing a fix | The contract comes first; nothing investigates |
| A test that reproduces the bug in the repo being fixed | Tickets start from the contract |
| Change one repo, never the others | The patch guard refuses changes outside the project, but nothing stops a write into a folder next to it |

Putting three repos into one context is not the answer for our models: GLM's window is 128k, and even where it fits, attention spread over three code bases reasons worse about each.

## Decision taken with the user

**One mission changes one repo.** The other repos are read-only context. A fix that belongs in another repo is a finding for that repo's team, not a change from here: one MR, one team reviewing it, the blast radius where everyone is looking.

## Proposal

### 1. The spec names its context repos

```markdown
## Context repos
- `../bot-sync-a` — pulls changes from the API every 5 minutes
- `../bot-sync-b` — pushes on webhook, retries 3 times
```

Paths are relative to the project. `scripts/factory/context.sh <mission>` checks each one exists and is a git checkout, records its commit in `.scratch/<mission>/context.tsv` (what the investigation read), and makes it read-only on disk for the mission (`chmod -R a-w`, restored by `context.sh <mission> --release`). The file system is the enforcement, not a prompt: a worker that tries to write there gets "Permission denied", whatever the tool.

Then two more barriers, as for everything else:
- the command guard refuses `write` and `edit` outside the project root, and git commands run in a context repo (`git -C`, `cd ../x && git`);
- the patch guard already refuses a patch reaching outside the project (D56).

### 2. An investigation step before the contract

For a mission whose spec has `## Context repos` and `**Intent:** bugfix` (or `exploration`), `next.sh` adds `investigate` before `contract`:

1. **Map, one fresh context per repo.** A `factory-explorer` agent per context repo, read-only, writes `.scratch/<mission>/context/<repo>.md`: how it reaches the API (endpoints, schedule, trigger), the data it sends and expects, its retries and timeouts, what it assumes about ordering and ownership, its configuration. Short, with `file:line` for every claim. One more explorer does the same for the home repo's side of each interaction.
2. **Reason over the briefs, not the code.** A `factory-investigator` reads the briefs and the symptom from the spec, and keeps `.scratch/<mission>/investigation.md`: the system map (who calls whom, in what order, with which data), and a hypothesis log, each hypothesis `supported`, `ruled out` or `open`, with its evidence. When it needs a detail, it writes a question for one repo; the factory sends it to a fresh explorer in that repo and appends the answer. No agent ever holds two repos.
3. **Reproduce in the home repo.** The step ends with a test in the home repo that fails for the stated reason (two simulated syncs racing on one record, a replayed webhook, an out-of-order update), committed as the mission's first ticket, red. P9's "reproduce first", applied to the whole mission.
4. **Conclude.** `investigation.md` ends with `## Conclusion`: the cause, where the fix belongs, and the assertions the fix must satisfy. If the fix belongs in a context repo, the mission stops at a human step with a finding written for that team (symptom, cause, evidence, suggested fix), and changes nothing.

The human approves the conclusion like a contract (a gate, counted in P8's five).

### 3. Then the usual mission, in the home repo

The contract author reads the conclusion: the assertions describe the home repo's behavior toward its callers ("a sync replayed twice creates no duplicate", "an update older than the stored one is refused"). The reproduction test is ticket 01; it must go green, and stay frozen afterwards (D93's frozen tests, for that one file). Reviewers and the steward get the context briefs, not the context repos.

## Why it suits our models

Each agent sees one repo, or short briefs. The investigator's context holds a few pages, not three code bases; follow-up questions go to fresh contexts. That is how a 128k model does what a large-window model does in one go, and usually with sharper reasoning, since nothing that matters is lost in the middle of a long context.

## Trade-offs

| For | Against |
|---|---|
| Cross-service bugs get a method: map, hypotheses with evidence, a reproduction | More steps before the first ticket; for a bug inside one repo, skip it (no `## Context repos`, no investigation) |
| One repo changes; the others are protected by the file system, the guard and the patch guard | The context repos must be cloned on the machine, at the right branch; `context.tsv` records which commit was read |
| The conclusion can say "not here", and hand a finding to the right team | Briefs can be wrong; each claim carries `file:line`, and the investigator re-checks the ones a hypothesis depends on |
| Small contexts for gateway models | Two new agents (explorer, investigator) to tune and probe |

## What it borrows

- From the user's own investigation with another agent: holding the whole system in view before fixing.
- From our waves and Machinist's handoffs: small fresh contexts, results in files.
- From P9: reproduce before fixing, a journal of what was tried and ruled out.

## Plan

1. `## Context repos` parsing, `context.sh` (check, record, read-only on disk, release), guard rules for writes and git outside the project. Tests. **S**
2. `factory-explorer` and `factory-investigator` agents and briefs; `investigate` step in `next.sh` and the workflow; the question → fresh explorer → answer loop. **M**
3. Reproduction ticket and its frozen test; the conclusion gate; the "fix belongs elsewhere" stop with a finding file. **S**
4. First real use: the API and its two sync bots. **S**

## Open questions

- Should the explorers run on the cheap worker model, or on a stronger one? Proposed: the worker model; the investigator on the heavy one.
- `chmod -R a-w` on a clone the human also works in: acceptable for the length of a mission, or clone the context repos into a factory folder instead? Proposed: a factory folder (`.factory/context/<repo>`, ignored), so the human's own clones are never touched.
- Investigation without a fix (pure exploration): stop after the conclusion, with the report as the deliverable?
