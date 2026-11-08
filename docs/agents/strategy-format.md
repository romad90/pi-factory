# Strategy format (the architect's plan for a job)

Written by `factory-architect` to `.scratch/<job>/strategy.md` from `job.md` (the person's one line) and `measures.md` (computed by `scripts/factory/measure.sh`, no model). Checked by `scripts/factory/strategy.mjs check` before a person sees it; approved with `/factory-approve <job> strategy`, which turns each mission below into its own `spec.md`. Keep the headings and field names exact: scripts read them.

```markdown
# Strategy: <job>

**Job:** <the person's line, verbatim>

## What the measurements say
- <one finding per line, each citing the measurement it comes from: [M-4]>

## Lenses
- **Software engineering:** <the question it answered> [M-…]
- **Reliability:** <the question it answered> [M-…]
- **Computer science:** not applied: <why, in one line>

## Options
### A. <short name>
**Value:** <what the codebase or the team gains, concretely> [M-…]
**Cost:** <missions, about how many tickets>
**Strength:** strong | worth exploring | speculative
**Risks:** <what could go wrong, and what is known not to be a risk>
**Trade-off:** <the quality it buys, and the one it pays with>
**Non-goals:** <what this option does not do>

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
**Done when:** `<a command that exits 0 only when the mission is done>` (verify.sh runs it, no model)
**Frozen paths:** <comma-separated, or ->
**Frozen tests:** <comma-separated, or -; required for a refactor>
**Reproduction:** <for a bugfix: the test that fails before the fix>

<The mission text: what to do and what not to do, in a few lines. It becomes the spec's problem statement, so it settles every decision a worker would otherwise ask about.>

### 2. <mission-name>
**After:** <mission-name>
…

## Decisions for the team
- <a choice that changes production behavior or belongs to the team (security defaults, a public API change): what, why it matters, which measurement shows it. No mission takes it.>
```

Rules the check enforces (what a reviewer of this plan would hold it to, written as code so nobody has to repeat it):

- At least two options; `**Chosen:**` names one of them, and not a speculative one.
- Each option has a value, a cost, a strength (strong, worth exploring, speculative), a trade-off and its non-goals (`Leaves out` is still read).
- Every `[M-n]` cited exists in `measures.md`; the findings, each option's value and the choice cite at least one.
- Each mission: a name in lowercase words and dashes, not used by an existing mission; a known intent; a `**Done when:**` with a command in backticks; a number for `**Max tickets:**`; `**After:**` naming an earlier mission or `-`; a refactor names its frozen tests.
- At most 4 missions. A job that needs more is two jobs.
- `## Lenses` names at least two lenses; an applied lens cites a measurement.
- A refactor doesn't touch a measured file whose mutation score is under the threshold (`FACTORY_PIN_THRESHOLD`, default 70), or isn't measured, unless an earlier maintenance or bugfix mission covers it.
- A measured risk of certificate checks turned off is named, by its id, under `## Decisions for the team`.
- A refactor of a library (shape) protects its public surface: its done condition holds a command that checks the API report (Hyrum's law).
- A bugfix names its `**Reproduction:**`, the test that fails before the fix.
- A done command gives Stryker one `--mutate`, the files joined by commas: a repeated `--mutate` keeps only the last.

Then a strategy critic (another model family, fresh context) attacks the plan; a `[blocking]` finding sends it back to the architect with the finding, before any person reads it.
