# P22. One entry, derived process: the change sets the tier, a function in code sets the steps

**Status:** proposed, after mission 5; the architect step is built (D105, below) · **Effort:** L · **Depends on:** the MR gate's lanes (behavior-paths), P20 (token budget), P21 (boundary detection); replaces the idea of risk tiers as a separate feature

## Problem

The lanes exist to make the process cost what the change risks: a typo shouldn't pay for a contract, a critic, tickets and a validator. The goal is right; the way is not.

| Today | What's wrong with it |
|---|---|
| The person picks the lane before starting: `/factory` (mission), `/factory-light` (a review of a hand change), `/factory-fix` (a small reviewed commit) | The author chooses the tier, against the factory's own rule that the change sets it. The choice is made before the answer is known. |
| `gate.sh mr` checks afterwards that a lane wasn't too light (behavior paths touched → a mission must be in the MR) | Enforcement exists only as a refusal at the end, after the work |
| Three entry points, three sets of docs, three folders (`.scratch/<f>`, `.scratch/light/<slug>`) | More to learn, and the light lanes' runs don't compare with missions in the data |
| Every MR needs a human to merge, and the number of approvals is left to the forge | Nothing says "auth, CI, deploy, migrations need two people", and nothing lets a docs-only change through with less |

Policy (how much scrutiny this change deserves) and mechanism (the steps that apply it) are mixed in the lanes. Separate them.

## Design

**One entry.** `/factory "<what>"` (or a spec, or an issue later, P16). The person describes the work; the factory derives the process.

**Decided twice, because blast radius is only certain after the change.**

1. **Predicted tier, at intake**, from the request and the spec: the intent (feature, bugfix, maintenance, refactor, docs), the paths and boundaries it names, its size. It plans the process: whether to deepen (D104), whether a contract, a design, how many tickets, which judges.
2. **Actual tier, from the diff, before the MR**, in code, the way `gate.sh` reads `behavior-paths` today. **It can only escalate.** A diff bigger or riskier than predicted adds the missing steps (a second review, the security axis, the validator), or stops the mission and says why. It never downgrades silently.

**The decision is a function, in code.** `tier = f(diff, paths, boundaries, intent, size)`, with its inputs:

| Input | Source |
|---|---|
| Paths | `.factory/risk-paths`: `high` (auth, CI, deploy, migrations, secrets handling, anything the project names), `low` (docs, tests only, comments); `behavior-paths` stays as the medium floor |
| Boundaries | P21's detection from the diff: input parsing, auth, outside calls, files, queries, processes |
| Size | lines and files changed, as the fix lane counts them today (D76) |
| Intent | the spec's `**Intent:**` |

A model may supply evidence (a boundary it saw) but never decides the tier. The function is tested like code, with a table of cases.

**Tiers map to steps and approvals:**

| Tier | Steps (derived) | Approvals (enforced by the forge) |
|---|---|---|
| low (docs, tests only, comments) | guard, lint, tests, one fresh review from another family | one person; auto-merge only after evidence (below) |
| medium (behavior paths, no boundary, no high path) | the mission as today, sized by P20 | one person |
| high (a high path or a boundary) | the mission, plus the security axis (P21), the validator, two judges of different families | two people (CODEOWNERS or the forge's approval rules) |

**It explains itself.** Each mission writes `.scratch/<f>/plan.md`: the tier, the inputs that set it ("medium: touches `src/api/*`, 3 files, no boundary"), the steps and the approvals. An escalation adds a line saying what changed and why. An opaque decision tree would be the lanes' problem again, hidden.

**What the person can do.** Raise the tier, never lower it. The fixed human gates stay: approving the contract when behavior changes, and the merge.

**The forge enforces the count.** The actual tier goes on the MR as a label (`factory:risk-high`); the forge's approval rules and CODEOWNERS require the approvals. The factory keeps not merging, and an agent's approval never counts as a person's.

**Auto-merge for low, only after evidence.** Start strict: low still needs one approval. Loosen when the record allows (no revert across N low-tier MRs), and tighten automatically when the revert rate of a tier rises: the circuit breaker the Claude Code team names as missing in its own process.

## The architect step (built, D105)

The tier decides how much process one change gets. Before that, a job has to become changes: which missions, in what order, and why. Missions 6 and 7 showed the cost of leaving that to the person: about three hours of measuring and planning each, and a mission that reran an earlier one's work because nobody had measured that the earlier one pinned too little (coverage, not mutation score).

- **One line in.** `/factory-job <name> "<what you want>"`.
- **Measured by scripts.** `measure.sh`: tests, history, per-file nesting, size, duplication, churn, importers, mutation score from the last report, the public surface, earlier missions. Each row has an id.
- **Planned by the architect.** Options with value, cost and what each leaves out; the choice; missions with done conditions that are commands; the team's decisions kept out of every mission.
- **Checked before a person sees it.** Every number cited must be a measured row; every mission must be runnable.
- **Approved once.** The specs are written from the strategy; the missions start at their contracts and run in order.

**How it thinks, without being steered (D106).** The person shouldn't have to tell the architect "this is a bot" or "pin before you refactor". So:

- **The shape is measured, not declared.** `measure.sh` reads the manifests: an API server, a bot, a batch or scheduled job, a library, a front end, a command-line tool, and what it talks to (databases, HTTP services, queues); the installed practice packs. Presets become evidence the architect reads.
- **Lenses, chosen and shown.** The architect composes the ways of looking a distinguished engineer would bring to this problem (software engineering: where change costs most; reliability: how it fails; computer science: invariants and complexity; security: boundaries and defaults; product), names them under `## Lenses` with the measurement behind each, and says which it left out and why.
- **Risks measured as leads.** Certificate checks turned off, outgoing calls whose file never sets a timeout, empty catch blocks, a library that exits the process: found by pattern, each with where.
- **Expectations held by code, not by repetition.** The check refuses a refactor of a file under the pin threshold without an earlier pinning mission, a plan without lenses, and a TLS risk not left to the team. Each rule is a case in the test suite's casebook; a new expectation becomes a new case, not a new instruction to remember.

Next, once the data supports it: the critic attacks the strategy as it attacks a contract, and the strategy's approval stands in for the missions' own approvals when the checks (P23) carry the missions' done conditions.

## Migration

1. **Shadow.** `/factory`, `/factory-light` and `/factory-fix` keep working; each also computes the derived tier and plan and writes them next to its own, without acting on them. A few missions compare the function's tiers with the person's lane choices; every disagreement is a case for the table.
2. **Take over.** One entry; the old commands become aliases that print the derived plan, then run it. `.scratch/light/` folds into `.scratch/`.
3. **Forge.** Labels and approval rules per tier, set by the project's owners (their decision, not the factory's).

## Outside checks

- The decision table's tests (code).
- Shadow phase: agreement between the derived tier and the person's choice; every disagreement explained, and the function changed only through a new test case.
- After takeover: revert and incident rate per tier (archive, metrics), and the human time per MR (approvals, waiting time). If reverts rise, the time wasn't saved, only moved.

## Not doing

- A model choosing the tier.
- Lowering a tier during a mission.
- The factory merging, or counting an agent's approval as a person's.
