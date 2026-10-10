# Factory cheat sheet

Everything you type, in the order you'll need it. Why each rule exists: [ADR-001](docs/adr/ADR-001-agentic-factory.md).

> **The one rule:** drive missions with `/factory …` commands in Pi. Don't run `!scripts/...` by hand mid-mission and don't commit mission files yourself. The scripts commit their own state, and the lead relays.

---

## 1. Who does what: manual, automatic, and why

You keep the decisions that define value and risk; the factory does everything that can be checked or repeated.

| Step | Who | Why it is that way |
|---|---|---|
| Grill the idea, write the spec (`/grill-with-docs`, `/to-spec`) | **You** | The spec decides what value is. A model guessing it would optimize the wrong thing. |
| Write the validation contract | Factory (author agent) | Mechanical translation of the spec into checkable assertions. |
| Attack the contract | Factory (critic, another family) | A second model family finds what the author can't see in its own work. |
| **Approve the contract (G1)** | **You, one word** | The definition of done is the highest-leverage artifact; a human owns it. |
| Write the tickets | Factory (ticket writer) | Sizing and ordering is repeatable work. |
| **Approve the tickets** | **You, one word** | Cheap to check, expensive to get wrong: a bad split costs rounds. |
| Coverage check (G2), tests configured | Factory (script) | Pure bookkeeping. |
| Build, integrate (lint, tests, extra check, patch guard) | Factory (workers + scripts) | Deterministic gates never get tired. |
| Code review per ticket (G3) | Factory (reviewer, another family) | Fresh eyes on every change, no bias from the builder. |
| **Answer a question a worker raised** | **You, one word** | Irreversible choices (deletes, secrets, production, the contract) never default. |
| Behavior validation (G4) | Factory (validator, holds the instrument) | Workers never see the tests they're judged by. |
| **Ship an assertion you can't prove yet** | **You** | Only a named human, on a date, accepts a known limit. |
| Fix tickets from findings (behavior or health) | Factory (ticket writer), **you approve** | One root cause, one ticket; your approval keeps the scope honest. |
| Code health (G5): ratchet, then steward | Factory (script, then steward on another family) | The codebase is the fuel; erosion is caught before it merges. |
| Escalation after 3 failed rounds | **You** | Repeated failure means the contract or the design is wrong, which is a human call. |
| Open the MR (`/pr`), merge | **You** | You sign what ships. |
| Retro (`/retro`) | **You** | Learning becomes rules only on a human's word. |
| Checkpoints, rounds, models in verdicts, notifications, pause/resume | Factory (scripts) | Bookkeeping a human used to do and forget. |

**Still manual, and planned:** opening the draft MR and reading red CI (needs a GitLab token, roadmap F13); a drift check of spec ↔ code before `/pr` (C10).

## 2. Once per laptop

```bash
pi install npm:pi-subagents@0.76.1       # remove @tintinweb/pi-subagents if present
scripts/factory/install-pi-config.sh     # worktree hook (hides instrument/), concurrency
```

Under a small shared quota (about 10 requests per window), set `parallel.concurrency: 1` in `~/.pi/agent/extensions/subagent/config.json` and `export FACTORY_MAX_PARALLEL=1`. The retry block in `.pi/settings.json` (6 × 5 s) absorbs short 429 bursts.

## 3. Once per template (your models)

| File | Set |
|---|---|
| `.pi/agents/factory/*.md` | `model:` and `thinking:` per agent (9 agents) |
| `.pi/settings.json` | `subagents.modelScope.allow: ["<your-provider>/*"]` |
| `.factory/model-families.json` | a `{ "match": "*name*", "family": "x" }` line per model you use |

`node scripts/factory/models-lint.mjs` must print `MODELS: PASS`. It enforces: critic ≠ author family; reviewer, review-axis, validator and code steward ≠ worker families; no `fallbackModels` line (removed upstream, stops the agent from launching); no `factory-*` in `agentOverrides` (crashes discovery).

**Model notes from mission 1:**

| Symptom | Fix |
|---|---|
| 400 on `reasoning_effort` | The model accepts only some levels (e.g. `high` or none): change `thinking:` |
| 422 `extra_forbidden` on `reasoning_content` | The model rejects replayed reasoning in multi-turn runs: `thinking: off` for that agent |
| Lead repeats itself ("20.20.20…") | Esc, new session, `/factory <feature>`. Use a steady model for the lead (medium thinking is enough) |
| Verdict names a model you don't use | Harmless since v1.0: `collect.sh` writes the configured model |

## 4. Once per target repo

```bash
scripts/factory/install-into.sh "/path/to/repo"     # from this template; quotes matter with spaces or &
```

That puts the install on its own branch, `chore/install-pi-factory-<version>`, as one commit (with today's health baseline). Merge it through its own MR before any mission. Then in the target:

1. `.factory/commands.env`: `FACTORY_TEST_CMD` (required), `FACTORY_LINT_CMD`, `FACTORY_EXTRA_CMD` (e.g. `helm lint --strict charts/x`), `FACTORY_HEALTH_CMD` (your complexity/duplication tool), `FACTORY_GATEWAY_URL` (pre-flight network check).
2. `.factory/behavior-paths`: regexes of paths that change behavior.
3. `docs/agents/quality-bar.md`: the bar G5 judges against. Sharpen it for this repo; keep the `QB-` IDs.
4. `.gitlab-ci.yml`: `include: [{ local: .factory/ci/factory.gitlab-ci.yml }]`, plus **Settings → Merge requests → Pipelines must succeed**.
5. In Pi, **trust the project** once, so the command guard (`.pi/extensions/factory-guard.ts`) loads.
6. `/setup-matt-pocock-skills`: choose the local markdown tracker in `.scratch/`.
7. `scripts/factory/doctor.sh` green, then in Pi: `/subagents-doctor`, `/subagents-models` (9 `factory-*` agents).

## 5. A mission

| # | You | Factory |
|---|---|---|
| 1 | `/grill-with-docs`, then `/to-spec` → `.scratch/<f>/spec.md` (start with `**Intent:** feature`) | |
| 2 | `/factory <f>` | pre-flight, contract author, then critic |
| 3 | Read the contract + critique. `/factory-approve <f>`, or `/factory-amend <f> "<change>"` | amend reruns author + critic |
| 4 | | ticket writer proposes tickets |
| 5 | Read `issues/` (edit, split, delete freely), then `/factory-approve <f> tickets` | coverage check |
| 6 | | build waves, integration, reviews, validation |
| 7 | Answer when notified: `/factory-decide <f> <answer> "<why>"` | logged in `decisions.tsv`, read by every role |
| 8 | At `STEP: unverified`: prove it, or `/factory-accept-unverified <f> <ids\|ALL> "<why>"` | listed as Known limits |
| 9 | Approve fix tickets when behavior or health finds something | fixes built, re-validated |
| 10 | | health ratchet, then code steward (G5) |
| 11 | At `STEP: pr`: `/pr`, open the MR (draft), then `/retro` | metrics printed |

Keep specs to roughly 12 stories or fewer; split anything bigger into two missions.

## 6. STEP codes

| STEP | Who | Means | Do |
|---|---|---|---|
| `paused` | lead | a pause note exists | lead resumes and continues |
| `grill` | you | no spec | `/grill-with-docs`, `/to-spec` |
| `contract` | lead | no contract, no critique, or a pending amendment | runs the contract wave |
| `approve` | you | G1 | `/factory-approve <f>` or `/factory-amend` |
| `decide` | you | a worker or reviewer asked something | `/factory-decide` |
| `tickets` | lead | no tickets | ticket writer drafts them |
| `approve-tickets` | you | tickets or fix tickets proposed | review `issues/`, `/factory-approve <f> tickets` |
| `coverage` | you | G2: an assertion uncovered or a ticket unjustified | fix `## Covers`, or amend |
| `setup` | you | `FACTORY_TEST_CMD` empty | fill `.factory/commands.env`, commit |
| `build` | lead | tickets ready | build wave → integrate each patch |
| `review` | lead | integrated tickets | review wave → `collect.sh` |
| `escalate` | you | 3 failed rounds | usually: split the ticket, amend the contract, or rethink the design |
| `blocked` | you | `## Blocked by` can't resolve | check for cycles |
| `validate` | lead | all tickets pass, or fixes built since a failing verdict | validator → `collect.sh` |
| `behavior-fix` | lead | behavior FAIL with findings | ticket writer drafts one fix ticket per finding |
| `behavior-stale` | lead | behavior paths changed after validation | re-validates |
| `unverified` | you | PASS left assertions or bar items unproven | prove, or accept |
| `health` | lead | no health report for the current code | `health.sh check` (no model) |
| `health-fix` | lead | ratchet or steward failed | ticket writer drafts fix tickets |
| `steward` | lead | no steward verdict for the current code | code steward → `collect.sh` |
| `pr` | you | all gates green | `/pr`, MR, `/retro` |

## 7. The quality bar (G5)

The codebase is the fuel that brings value to customers, so every mission must leave it **safe, understandable by any human, battle-tested and predictable**. Two layers:

- **Measured (no model):** `health.sh check` compares duplication, large files, deep nesting, debt markers and skipped tests to `.factory/health-baseline.json`. A mission may improve them, never make them worse. Your repo tool (`FACTORY_HEALTH_CMD`) must pass too. A justified exception: a human runs `scripts/factory/health.sh baseline` and commits it with the reason.
- **Judged:** the code steward (fresh, on another family than the workers) reads the whole mission diff against `docs/agents/quality-bar.md`. Every `QB-` item gets evidence or a label, and every changed source file gets a three-sentence explanation. A file it can't explain fails the gate: a human wouldn't understand it either.

## 8. Safety: what agents can never do

| Layer | When | What it stops |
|---|---|---|
| **Command guard** (`.pi/extensions/factory-guard.ts`) | Live, on every tool call of the lead and agents | push, force, `--no-verify`, history rewrites, `sudo`, recursive deletes of `/ ~ .. .git`, cluster/cloud/secret-store changes, uploads and remote shells, reading credentials or `.env`, publishing, merging, writing to the factory, CI or hooks, any route to `instrument/` from a worker |
| **Patch guard** (`patch-guard.sh`) | Every worker patch, every fix-lane change | changes to the instrument, the factory, CI or hooks; deleted, skipped or focused tests; silenced checks (`eslint-disable`, `@ts-ignore`, `noqa`, …); anything that looks like a secret |
| **CI gate** | Every MR | all of G1–G5, lanes, instrument rule |

A blocked agent stops and asks; it never looks for another way. Blocks are logged in `.pi-subagents/guard.log`, and patch-guard blocks count as failed rounds in the metrics. The guard loads only once the project is trusted in Pi; the patch guard holds either way. Working on the factory itself in Pi: start Pi with `FACTORY_GUARD=off` (maintainers only, never in a target repo).

## 9. Small changes: the fix lane

```text
/factory-fix <slug> start "<what>"   [--mission <f>]
… make the smallest change, commit it (fix(scope): …) …
/factory-fix <slug> check
```

`check` blocks anything that touches behavior paths or `instrument/`, changes more than 80 lines (`FACTORY_FIX_MAX_LINES`), or fails the patch guard (skips, silenced checks, secrets, deleted tests). Otherwise it runs lint, tests and the extra check, then one fresh reviewer from another family. The verdict lands in `.scratch/light/<slug>/verdicts/code.md`, and the MR gate checks it.

## 10. Commands you may run yourself

| Command | When |
|---|---|
| `scripts/factory/next.sh <f>` | where is this mission? |
| `scripts/factory/doctor.sh [--quick]` | after install or a model change / before a run |
| `scripts/factory/gate.sh mission <f>` | the gate CI will run |
| `scripts/factory/metrics.sh <f>` | numbers for the MR |
| `scripts/factory/health.sh metrics` | today's health metrics for the repo |
| `scripts/factory/readiness.sh` | what the repo still lacks for Step 2 |
| `scripts/factory/skills-pin.sh verify\|check-global` | skills drifted or shadowed? |

## 11. Gates and lanes

- **G1** critique present, approved by a human.
- **G2** every assertion covered, every ticket justified; tests configured.
- **G3** each ticket PASS on its latest integration commit, with a generated brief id, recorded by `collect.sh`.
- **G4** behavior PASS, recorded, generated brief, every assertion proven or accepted, and no behavior change since.
- **G5** health report PASS (ratchet + repo tool), steward PASS, recorded, generated brief, every bar item proven or accepted, every changed source file explained, and no source change since.
- **Lanes (MR):** behavior paths touched → a mission must be in the MR. Otherwise a light review is needed. Fix-lane reviews are checked either way. Changing or deleting an instrument case needs `**Amended:**` or `**Withdrawn:**` in the same MR. The `factory:bypass` label skips the gates, visibly.

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `PREFLIGHT: FAIL … gateway unreachable` | VPN or network | reconnect, `/factory <f>` |
| "blocked by the factory guard" | an agent tried something on the deny-list | read what it needed; if legitimate, you do it by hand (or through the fix lane) |
| `patch blocked` in a verdict | worker touched CI, a test or the factory | recorded as a round; the next build sees the reason |
| `STEP: health-fix` after a refactor | a metric got worse | fix tickets, or a justified new baseline committed by you |
| Gate: "no explanation for: …" | steward skipped a changed file | rerun the steward (`workflow.sh steward`) |
| Red band "workflow: true needs one fenced block" | lead pasted a script | playbook passes `WORKFLOW_FILE` paths; if it persists, update the factory |
| `Builtin override 'factory-…'` | models in `agentOverrides` | `node scripts/factory/migrate-models.mjs` |
| Skills listed as agents, builtins visible | repo has no `.pi/`, discovery walked up to `~/.agents` | install the factory in the repo |
| `skills-pin` fails after `npx skills add` | it installs `main`, not v1.3.1 | install from the v1.3.1 tag; `skills-pin.sh check-global` |
| Worker returns no patch | run ended on a thinking-only turn, or ticket too big | recorded automatically as a round; round 2 goes to the heavy worker |
| Gate: "verdict not recorded" | `collect.sh` didn't run | `scripts/factory/collect.sh <f>` |
| 429 rate limit | shared quota | concurrency 1, `FACTORY_MAX_PARALLEL=1` |
| `not a git repo` from install | unquoted path with spaces or `&` | `cd` into it, pass `"$PWD"` |
| Lead context above 70% | long mission | it pauses itself; `/factory <f>` in a new session |

## 13. Where things live

```
.scratch/<f>/spec.md                 spec + validation contract (+ approval, accepted-unverified lines)
.scratch/<f>/contract-critique.md    critic's findings
.scratch/<f>/issues/NN-slug.md       tickets (docs/agents/ticket-format.md)
.scratch/<f>/verdicts/               <ticket>-code.md, behavior.md, health.md (+ .rN.md history)
.scratch/<f>/health/report.md        ratchet and repo tool results (G5)
.scratch/<f>/decisions.tsv           every human decision, status unreviewed → promoted
.scratch/<f>/state/                  integration markers, open question, tickets pending, PAUSED.md
.scratch/<f>/workflows/              every workflow that ran (audit)
.scratch/light/<slug>/               fix lane: request, blast radius, verdict
docs/agents/quality-bar.md           the bar G5 judges against (repo-owned)
.factory/health-baseline.json        the ratchet (repo-owned)
instrument/scenarios/                behavior cases (validator only)
```
