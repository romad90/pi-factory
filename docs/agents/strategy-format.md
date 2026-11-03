# Strategy format (the architect's plan for a job)

Written by `factory-architect` to `.scratch/<job>/strategy.md` from `job.md` (the person's one line) and `measures.md` (computed by `scripts/factory/measure.sh`, no model). Checked by `scripts/factory/strategy.mjs check` before a person sees it; approved with `/factory-approve <job> strategy`, which turns each mission below into its own `spec.md`. Keep the headings and field names exact: scripts read them.

```markdown
# Strategy: <job>

**Job:** <the person's line, verbatim>

## What the measurements say
- <one finding per line, each citing the measurement it comes from: [M-4]>

## Options
### A. <short name>
**Value:** <what the codebase or the team gains, concretely> [M-…]
**Cost:** <missions, about how many tickets, the risk>
**Leaves out:** <what this option does not do>

### B. <short name>
… (two or three options; one may be "do less" or "do nothing yet")

## Choice
**Chosen:** A
<why, against the other options, citing measurements [M-…]>

## Missions
### 1. <mission-name>
**Intent:** maintenance | refactor | feature | bugfix
**After:** -
**Max tickets:** 12
**Scope:** <files or folders, from the measurements>
**Done when:** `<a command a script runs>` <and its pass condition>
**Frozen paths:** <comma-separated, or ->
**Frozen tests:** <comma-separated, or -; required for a refactor>

<The mission text: what to do and what not to do, in a few lines. It becomes the spec's problem statement, so it settles every decision a worker would otherwise ask about.>

### 2. <mission-name>
**After:** <mission-name>
…

## Decisions for the team
- <a choice that changes production behavior or belongs to the team (security defaults, a public API change): what, why it matters, which measurement shows it. No mission takes it.>
```

Rules the check enforces:

- At least two options; `**Chosen:**` names one of them.
- Every `[M-n]` cited exists in `measures.md`; the findings, each option's value and the choice cite at least one.
- Each mission: a name in lowercase words and dashes, not used by an existing mission; a known intent; a `**Done when:**` with a command in backticks; a number for `**Max tickets:**`; `**After:**` naming an earlier mission or `-`; a refactor names its frozen tests.
- At most 4 missions. A job that needs more is two jobs.
