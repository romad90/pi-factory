# Factory cheat sheet

Everything you type, in the order you'll need it. Why each rule exists: [ADR-001](docs/adr/ADR-001-agentic-factory.md).

> **The one rule:** drive missions with `/factory …` commands in Pi. Don't run `!scripts/...` by hand mid-mission and don't commit mission files yourself. The scripts commit their own state, and the lead relays.

---

## 1. Once per laptop

```bash
pi install npm:pi-subagents@0.76.1       # remove @tintinweb/pi-subagents if present
scripts/factory/install-pi-config.sh     # worktree hook (hides instrument/), concurrency
```

Under a small shared quota (about 10 requests per window), set `parallel.concurrency: 1` in `~/.pi/agent/extensions/subagent/config.json` and `export FACTORY_MAX_PARALLEL=1`. The retry block in `.pi/settings.json` (6 × 5 s) absorbs short 429 bursts.

## 2. Once per template (your models)

| File | Set |
|---|---|
| `.pi/agents/factory/*.md` | `model:` and `thinking:` per agent |
| `.pi/settings.json` | `subagents.modelScope.allow: ["<your-provider>/*"]` |
| `.factory/model-families.json` | a `{ "match": "*name*", "family": "x" }` line per model you use |

`node scripts/factory/models-lint.mjs` must print `MODELS: PASS`. It enforces: critic ≠ author family; reviewer, review-axis and validator ≠ worker families; no `fallbackModels` line (removed upstream, stops the agent from launching); no `factory-*` in `agentOverrides` (crashes discovery).

**Model notes from mission 1:**

| Symptom | Fix |
|---|---|
| 400 on `reasoning_effort` | The model accepts only some levels (e.g. `high` or none): change `thinking:` |
| 422 `extra_forbidden` on `reasoning_content` | The model rejects replayed reasoning in multi-turn runs: `thinking: off` for that agent |
| Lead repeats itself ("20.20.20…") | Esc, new session, `/factory <feature>`. Use a steady model for the lead (medium thinking is enough) |
| Verdict names a model you don't use | Harmless since v1.0: `collect.sh` writes the configured model |

## 3. Once per target repo

```bash
scripts/factory/install-into.sh "/path/to/repo"     # from this template; quotes matter with spaces or &
```

That puts the install on its own branch, `chore/install-pi-factory-<version>`, as one commit. Merge it through its own MR before any mission. Then in the target:

1. `.factory/commands.env`: `FACTORY_TEST_CMD` (required), `FACTORY_LINT_CMD`, `FACTORY_EXTRA_CMD` (e.g. `helm lint --strict charts/x`), `FACTORY_GATEWAY_URL` (pre-flight network check).
2. `.factory/behavior-paths`: regexes of paths that change behavior.
3. `.gitlab-ci.yml`: `include: [{ local: .factory/ci/factory.gitlab-ci.yml }]`, plus **Settings → Merge requests → Pipelines must succeed**.
4. `/setup-matt-pocock-skills`: choose the local markdown tracker in `.scratch/`.
5. `scripts/factory/doctor.sh` green, then in Pi: `/subagents-doctor`, `/subagents-models` (7 `factory-*` agents).

## 4. A mission

| # | You | Factory |
|---|---|---|
| 1 | `/grill-with-docs`, then `/to-spec` → `.scratch/<f>/spec.md` (start with `**Intent:** feature`) | |
| 2 | `/factory <f>` | pre-flight, contract author, then critic |
| 3 | Read the contract + critique. `/factory-approve <f>`, or `/factory-amend <f> "<change>"` | amend reruns author + critic |
| 4 | `/to-tickets`: each ticket has `## Covers` (VAL IDs) or `## Covers: enabler` + why; `## Blocked by` for order | coverage check |
| 5 | `/factory <f>` | build waves, integration, reviews, validation |
| 6 | Answer when notified: `/factory-decide <f> <answer> "<why>"` | logged in `decisions.tsv`, read by every role |
| 7 | At `STEP: unverified`: prove it, or `/factory-accept-unverified <f> <ids\|ALL> "<why>"` | listed as Known limits |
| 8 | At `STEP: pr`: `/pr`, open the MR (draft), then `/retro` | metrics printed |

Keep specs to roughly 12 stories or fewer; split anything bigger into two missions.

## 5. STEP codes

| STEP | Who | Means | Do |
|---|---|---|---|
| `paused` | lead | a pause note exists | lead resumes and continues |
| `grill` | you | no spec | `/grill-with-docs`, `/to-spec` |
| `contract` | lead | no contract, no critique, or a pending amendment | runs the contract wave |
| `approve` | you | G1 | `/factory-approve` or `/factory-amend` |
| `decide` | you | a worker or reviewer asked something | `/factory-decide` |
| `tickets` | you | no tickets | `/to-tickets` |
| `coverage` | you | G2: an assertion uncovered or a ticket unjustified | fix `## Covers`, or amend |
| `setup` | you | `FACTORY_TEST_CMD` empty | fill `.factory/commands.env`, commit |
| `build` | lead | tickets ready | build wave → integrate each patch |
| `review` | lead | integrated tickets | review wave → `collect.sh` |
| `escalate` | you | 3 failed rounds | usually: split the ticket or amend the contract |
| `blocked` | you | `## Blocked by` can't resolve | check for cycles |
| `validate` | lead | all tickets pass | validator → `collect.sh` |
| `behavior-fix` | you | behavior FAIL with findings | one `NN-fix-<slug>.md` ticket per finding |
| `behavior-stale` | lead | behavior paths changed after validation | re-validates |
| `unverified` | you | PASS left assertions unproven | harness, or accept |
| `pr` | you | all gates green | `/pr`, MR, `/retro` |

## 6. Small changes: the fix lane

```text
/factory-fix <slug> start "<what>"   [--mission <f>]
… make the smallest change, commit it (fix(scope): …) …
/factory-fix <slug> check
```

`check` blocks anything that touches behavior paths or `instrument/`, or changes more than 80 lines (`FACTORY_FIX_MAX_LINES`). Otherwise it runs lint, tests and the extra check, then one fresh reviewer from another family. The verdict lands in `.scratch/light/<slug>/verdicts/code.md`, and the MR gate checks it.

## 7. Commands you may run yourself

| Command | When |
|---|---|
| `scripts/factory/next.sh <f>` | where is this mission? |
| `scripts/factory/doctor.sh [--quick]` | after install or a model change / before a run |
| `scripts/factory/gate.sh mission <f>` | the gate CI will run |
| `scripts/factory/metrics.sh <f>` | numbers for the MR |
| `scripts/factory/readiness.sh` | what the repo still lacks for Step 2 |
| `scripts/factory/skills-pin.sh verify\|check-global` | skills drifted or shadowed? |

## 8. Gates and lanes

- **G1** critique present, approved by a human.
- **G2** every assertion covered, every ticket justified; tests configured.
- **G3** each ticket PASS on its latest integration commit, with a generated brief id, recorded by `collect.sh`.
- **G4** behavior PASS, recorded, generated brief, every assertion proven or accepted, and no behavior change since.
- **Lanes (MR):** behavior paths touched → a mission must be in the MR. Otherwise a light review is needed. Fix-lane reviews are checked either way. Changing or deleting an instrument case needs `**Amended:**` or `**Withdrawn:**` in the same MR. The `factory:bypass` label skips the gates, visibly.

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `PREFLIGHT: FAIL … gateway unreachable` | VPN or network | reconnect, `/factory <f>` |
| Red band "workflow: true needs one fenced block" | lead pasted a script | playbook passes `WORKFLOW_FILE` paths; if it persists, update the factory |
| `Builtin override 'factory-…'` | models in `agentOverrides` | `node scripts/factory/migrate-models.mjs` |
| Skills listed as agents, builtins visible | repo has no `.pi/`, discovery walked up to `~/.agents` | install the factory in the repo |
| `skills-pin` fails after `npx skills add` | it installs `main`, not v1.3.1 | install from the v1.3.1 tag; `skills-pin.sh check-global` |
| Worker returns no patch | run ended on a thinking-only turn, or ticket too big | recorded automatically as a round; round 2 goes to the heavy worker |
| Gate: "verdict not recorded" | `collect.sh` didn't run | `scripts/factory/collect.sh <f>` |
| 429 rate limit | shared quota | concurrency 1, `FACTORY_MAX_PARALLEL=1` |
| `not a git repo` from install | unquoted path with spaces or `&` | `cd` into it, pass `"$PWD"` |
| Lead context above 70% | long mission | it pauses itself; `/factory <f>` in a new session |

## 10. Where things live

```
.scratch/<f>/spec.md                 spec + validation contract (+ approval, accepted-unverified lines)
.scratch/<f>/contract-critique.md    critic's findings
.scratch/<f>/issues/NN-slug.md       tickets
.scratch/<f>/verdicts/               <ticket>-code.md (+ .rN.md history), behavior.md
.scratch/<f>/decisions.tsv           every human decision, status unreviewed → promoted
.scratch/<f>/state/                  integration markers, open question, PAUSED.md
.scratch/<f>/workflows/              every workflow that ran (audit)
.scratch/light/<slug>/               fix lane: request, blast radius, verdict
instrument/scenarios/                behavior cases (validator only)
```
