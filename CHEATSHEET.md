# Factory cheat sheet

Everything you type, in the order you'll need it. Why the factory works this way: [DESIGN.md](docs/DESIGN.md); every decision in order: [ADR-001](docs/adr/ADR-001-agentic-factory.md).

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
| Write the program design: call stacks, files, signatures, slices (feature, refactor) | Factory (designer) | The model drafts the shape of the code in minutes; arguing with it costs ten. |
| **Approve the design (G1b)**, ideally with the MR's reviewer | **You, one word** | Every decision taken here is one the reviewer would otherwise make in code review, when changing it costs most (D94, D95). |
| Write the tickets, as vertical slices | Factory (ticket writer) | Sizing and ordering is repeatable work; each ticket runs end to end. |
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

**Watch:** `scripts/factory/cockpit.sh`, then open http://127.0.0.1:7357 (leads → mission → ticket; keys L M R Esc; read-only, D90). **Without a lead:** `scripts/factory/run.sh <mission>` runs the same loop as `/factory` with no model for the lead, and stops at your steps (D91); run it again after you act. **One command:** `scripts/factory/mr.sh <mission>` pushes the branch and opens the MR from `/pr`'s body (`.scratch/<mission>/pr.md`), with glab, a GitLab token, or push options (D86); rerun it after editing the body. **Still manual, and planned:** reading red CI (roadmap F13); a drift check of spec ↔ code before `/pr` (C10).

## 2. Which lane for which problem

The goal is not more code, faster: it is the day correction and maintenance run in the background and the team spends its time elsewhere (INTENT.md in the factory repo). Each lane removes one kind of human work. Pick the lane by the problem, not by the size of the change. The read-only prompts are installed in `docs/factory/prompts/` (in the factory repo: `docs/prompts/`); proposals are in the factory repo, `docs/proposals/`.

| Problem | Lane | Start with | You get | Status |
|---|---|---|---|---|
| New behavior to build | **Feature mission** | `/grill-with-docs`, `/to-spec` (`**Intent:** feature`), `/factory <f>` | contract, tickets, tested and reviewed code, MR | available |
| Legacy code nobody dares to change | **Maintenance mission** (characterization) | spec with `**Intent:** maintenance`, `/factory <f>` | tests that pin today's behavior, bugs included; glossary and docs. `src/` is frozen (D61) | available; a lane of its own is planned (proposal P3) |
| Change the structure of code whose behavior is pinned; bring it under `AGENTS.md` | **Refactor mission** | spec with `**Intent:** refactor` and `## Frozen tests` (the characterization tests), `/factory <f>` | the same behavior, new structure, every `AGENTS.md` rule it applies cited; the frozen tests never change (D93) | available |
| A bug between services: this repo and the repos that call it or sync with it | **Investigation across services** | spec with `**Intent:** bugfix` (or `exploration`) and `## Context repos`, `/factory <f>` | read-only clones, one brief per repo, a hypothesis log, a reproduction test here, a conclusion you approve; a fix elsewhere becomes a finding for that team (D99) | available |
| A small, contained fix | **Fix lane** | `/factory-fix <slug> start "<what>"` | one reviewed commit, at most 80 lines, no behavior path touched | available |
| A change made by hand needs a second pair of eyes | **Light review** | `/factory-light <slug> <base>` | a verdict from another model family, checked by the MR gate | available |
| You don't know where a repo is weak | **Audit and gaps** (read-only) | the `audit-gaps.md` prompt, with any agent | findings with evidence, the characterization test and acceptance criteria for each, questions | prompt available; becomes the discovery phase of proposal P3 |
| Secrets or personal data could leak | **Security audit** (read-only) | gitleaks or trufflehog first, then the `security-audit.md` prompt | leaks with evidence (never the value), secrets to rotate | prompt available; scanners in the gates planned (proposal P7) |
| "Done", but does the service start? | **Launch gate** (G6) | `FACTORY_BUILD_CMD`, `FACTORY_LAUNCH_CMD` | build, boot and smoke in a sandbox before `/pr` | planned (proposal P7) |
| The code erodes slowly | **Continuous improvement** | the strategist, between missions | draft MRs for one improvement at a time, never merged by the factory | planned (proposal P5) |
| An alert in production | **Incident lane** | a labeled issue (`factory:incident`) | a test that reproduces it, a fix, a draft MR; deploying stays human | planned (proposal P6) |
| The same change across many repos | **Cross-repo** | one plan, one mission per repo | one MR per repo | planned (proposal P4) |

### The legacy chain

Legacy code is where most of the work is, and where a fix most easily breaks something else. The lanes chain in a fixed order:

```text
audit and gaps  →  you triage  →  characterization  →  refactor  →  fix missions  →  launch gate
  (read-only)      (decisions)    (freeze behavior)    (new shape,  (red, then green)  (it runs)
                                                      same tests)
```

1. **Audit and gaps** finds the problems and proves each one with `file:line`. It changes nothing.
2. **You triage.** Check three or four findings by hand, answer the questions, set aside what is intentional. Only CONFIRMED findings, or findings you checked, go further. A PROBABLE finding turned into a ticket sends workers after a problem that may not exist.
3. **Characterization** freezes today's behavior in tests, defects included. Without it, a fix can break another mode and nobody sees it.
4. **Fix missions** take the confirmed findings as spec (`/to-spec`, then the usual contract and tickets). Each fix starts with a test that fails on today's code and passes after. The characterization test that pinned the defect turns red on purpose: update it in the same MR, and say so.
5. **Launch gate** proves the fixed service still builds and starts.

The audit report is input for the spec, not a replacement for it: the contract and its approval (G1) still decide what "done" means.

## 3. Once per laptop

```bash
pi install npm:pi-subagents@0.76.1       # remove @tintinweb/pi-subagents if present
scripts/factory/install-pi-config.sh     # worktree hook (hides instrument/), concurrency
```

Under a small shared quota (about 10 requests per window), set `parallel.concurrency: 1` in `~/.pi/agent/extensions/subagent/config.json` and `FACTORY_MAX_PARALLEL=1` in `.factory/commands.env` (or exported). The retry block in `.pi/settings.json` (6 × 5 s) absorbs short 429 bursts. When the provider stops a worker anyway, the lead runs `record-no-patch.sh <mission> <ticket> --provider "<error>"`: no round is lost, the mission pauses, and `/factory <mission>` resumes it once the limit resets.

After any model change, probe the gateway once: `doctor.sh` (full) runs `models-probe.mjs --stamp`, then commit `.factory/models-probe.ok`. It needs `FACTORY_GATEWAY_URL` (OpenAI-compatible base, e.g. `https://host/v1`) in `.factory/commands.env` and the key in the variable named by `FACTORY_GATEWAY_KEY_ENV` (default `OPENAI_API_KEY`). The pre-flight refuses to start a mission whose models changed since the last probe.

## 4. Once per machine (your models)

| File | Set |
|---|---|
| `.pi/agents/factory/*.md` | `model:` and `thinking:` per agent (11 agents) |
| `.pi/settings.json` | `subagents.modelScope.allow: ["<your-provider>/*"]` |
| `.factory/model-families.json` | a `{ "match": "*name*", "family": "x" }` line per model you use |

`node scripts/factory/models-lint.mjs` must print `MODELS: PASS`. It enforces: critic ≠ author family; reviewer, review-axis, validator and code steward ≠ worker families; no `fallbackModels` line (removed upstream, stops the agent from launching). It reads the model each agent really runs: its frontmatter, then `subagents.agentOverrides` in your user settings, then in the project's (D92; pi-subagents 0.76.1 applies them to `factory-*` agents).

**Set them once, reuse them everywhere.** In a repo where `MODELS: PASS`, run `node scripts/factory/models-profile.mjs capture`: it saves the models, thinking levels, scope and families to `~/.pi-factory/models.json` (outside every repo; `PI_FACTORY_MODELS` overrides the path). From then on, `install-into.sh` applies the profile to each new repo. To refresh a repo after changing the profile: `node scripts/factory/models-profile.mjs apply`, then the lint.

**Models per machine, never pulled from another one (D92).** `node scripts/factory/models-profile.mjs apply --user` writes the profile into your Pi user settings (`~/.pi/agent/settings.json`, `subagents.agentOverrides` and `modelScope`). They win over the agent files in every repo on this machine, copied or on the package, so a `git pull` can no longer bring the Mac's models to the cloud machine. A project's own `agentOverrides` still win over yours.

**Probe your models before a mission:** `node scripts/factory/models-probe.mjs --stamp`, then commit `.factory/models-probe.ok`. Each agent is probed on its own provider from Pi's `~/.pi/agent/models.json` (D79): served to your key, thinking level accepted, tool turns accepted. Run it on every machine you use: two machines can have two keys with different model lists.

**Choosing models (missions 1 and 2):**

| Role | What matters | Seen |
|---|---|---|
| Lead (your Pi session) | Follows instructions over a long session; stops when a rule says stop | gpt-oss-120b improvised and invented a report; GLM stopped and quoted the rule every time. Low thinking is enough |
| Worker | Cheap, good on routine tickets | Qwen 27B passed most tickets in one or two rounds |
| Heavy worker (round 2+, `Size: L`) | The strongest coder you have | GLM fixed in 7 minutes a ticket Qwen failed three rounds on |
| Judges (reviewer, axes, validator, steward, critic) | Another family than the workers; reliable verdict format | Gemma, all mission |

**Model notes from mission 1:**

| Symptom | Fix |
|---|---|
| 400 on `reasoning_effort` | The model accepts only some levels (e.g. `high` or none): change `thinking:` |
| 422 `extra_forbidden` on `reasoning_content` | The model rejects replayed reasoning in multi-turn runs: `thinking: off` for that agent |
| Lead repeats itself ("20.20.20…") | Esc, new session, `/factory <feature>`. Use a steady model for the lead (medium thinking is enough) |
| Verdict names a model you don't use | Harmless since v1.0: `collect.sh` writes the configured model |

## 5. Once per target repo

```bash
scripts/factory/install-into.sh "/path/to/repo" [--pack api|batch]...   # quotes matter with spaces or &
```

The target is a repo root, or **a project folder inside a monorepo**: then everything is scoped to that folder (diffs, gates, health, patches, the instrument wall), its CI jobs are named after it and run only when it changed, and nothing outside it is touched (D56). `AGENTS.md` gets a "Monorepo project" note: wherever a skill or doc says "repo root", agents read it as the project folder. After upgrading, run `scripts/factory/install-pi-config.sh` once on each machine so the worktree hook finds monorepo projects. That puts the install on its own branch, `chore/install-pi-factory-<version>`, as one commit (with today's health baseline). Merge it through its own MR before any mission. Then in the target:

1. `.factory/commands.env`: `FACTORY_TEST_CMD` (required), `FACTORY_LINT_CMD`, `FACTORY_EXTRA_CMD` (e.g. `helm lint --strict charts/x`), `FACTORY_HEALTH_CMD` (your complexity/duplication tool), `FACTORY_GATEWAY_URL` (pre-flight network check).
2. `.factory/behavior-paths`: regexes of paths that change behavior.
3. `docs/agents/quality-bar.md`: the bar G5 judges against. Sharpen it for this repo; keep the `QB-` IDs. With a pack, also prune `docs/agents/contract-checklist-<pack>.md` and `quality-bar-<pack>.md` (blank page: keep them; existing code: drop what contradicts it). Company-wide taste goes in `AGENTS.md`.
4. `.gitlab-ci.yml`: `include: [{ local: .factory/ci/factory.gitlab-ci.yml }]` (monorepo: `include` the project's own `<project>/.factory/ci/factory.gitlab-ci.yml` from the CI that runs for it; the path is printed at install). **If that CI runs as a child pipeline** (`trigger: include:` in the root CI), install with `--ci child`, and give the parent's trigger job `variables: { FACTORY_MR_TARGET: $CI_MERGE_REQUEST_TARGET_BRANCH_NAME, FACTORY_MR_LABELS: $CI_MERGE_REQUEST_LABELS }` and `strategy: depend`: without them the gates never start, or never block the MR (D57), plus **Settings → Merge requests → Pipelines must succeed**.
Rate limits: the install adds Pi's retry to `.pi/settings.json` (`"retry": { "enabled": true, "maxRetries": 6, "baseDelayMs": 5000 }`), so a 429 waits and retries instead of failing a wave. Tune it to your quota; an existing `retry` is kept.
5. In Pi, **trust the project** once, so the command guard (`.pi/extensions/factory-guard.ts`) loads. The benchmark needs it too: its agents run in worktrees of this repo, and bench refuses a case without the guard (D101).
6. `/setup-matt-pocock-skills`: choose the local markdown tracker in `.scratch/`.
7. `scripts/factory/doctor.sh` green, then in Pi: `/subagents-doctor`, `/subagents-models` (9 `factory-*` agents).

### Or: install once per machine, onboard projects (D92, opt-in)

The factory as a Pi package: agents, prompts, skills and the command guard load from it; scripts, briefs and the factory's docs reach the project as local links (untracked, in `.git/info/exclude`). A project carries only its own files (about 10), and a factory release changes no project.

```bash
git clone <pi-factory or your mirror> ~/pi-factory          # once per machine (or git pull to upgrade)
pi install ~/pi-factory                                      # Pi loads it in place
alias factory="$HOME/pi-factory/scripts/factory/factory.sh"  # in your shell profile
factory models apply --user                                  # your models, from ~/.pi-factory/models.json
scripts/factory/install-pi-config.sh                         # worktree hook (once)
```

Then, in each project folder (a monorepo project: its folder), on its own branch:

```bash
factory onboard              # a new project; --ci child as above
factory onboard --migrate    # a project the factory was copied into: git rm the copies, then onboard
```

It ends with **`factory setup`** (D102): the project's test, test-files and lint commands, found in its manifests and CI file, then rehearsed as a worker runs them (fresh worktree, offline, no credentials, green twice, red with a planted failing test). Read `.factory/setup.md`: the decisions first (a test runner that isn't a dependency, an install script that writes, a CI job a branch push starts), then `factory setup --write` puts the commands that passed into `.factory/commands.env` (never over a value you set), then `factory health baseline`. Run `factory setup` again after each decision, or after changing the test setup.

```bash
factory setup                # discover and rehearse; writes .factory/setup.md
factory setup --write        # and the commands that passed, into empty FACTORY_* lines
factory report               # stuck? one redacted text block to share instead of screenshots (--full for everything)
```

It writes `.factory/commands.env`, `behavior-paths`, `model-families.json`, `VERSION` (the factory version the project expects), `package-sha` (the factory commit CI runs), the CI include, `docs/agents/quality-bar.md`, a `GLOSSARY.md` stub, the `AGENTS.md` pointer and the `.pi/settings.json` subagents block, links the rest, and never commits (with `--migrate` it stages the `git rm` of the copies): review, commit, MR. In CI the factory jobs fetch the factory from `FACTORY_PACKAGE_GIT` (a CI/CD variable you set to a URL your CI may reach, e.g. your mirror; no default) at the commit in `.factory/package-sha`, check that commit, then link it; models stay per machine, checked by each pre-flight. `onboard` writes `package-sha` from your factory checkout: commit it with the rest. **Upgrade:** `git pull` in `~/pi-factory`, then `factory onboard` in each project when you want it to move up (bumps `.factory/VERSION` and the CI include, its own MR). The pre-flight refuses an installed factory older than the project expects, and checks the links (`factory link` repairs them). `factory version` shows both; `factory <script>` runs any factory script (`factory next <mission>`, `factory mr <mission>`).

## 6. A mission

| # | You | Factory |
|---|---|---|
| 1 | Optional, for anything bigger than a fix: `/skill:deep-prompt` → `.scratch/<f>/depth.md` (expert moves, raw material, methods, the outside check). Then `/grill-with-docs` on that file, then `/to-spec` → `.scratch/<f>/spec.md` (start with `**Intent:** feature`) | |
| 2 | `/factory <f>` | pre-flight, contract author, then critic |
| 3 | Read the contract + critique. `/factory-approve <f>`, or `/factory-amend <f> "<change>"` | amend reruns author + critic |
| 3b | Feature or refactor: read `design.md` (with the MR's reviewer if the spec names one), then `/factory-approve <f> design`, or edit it | designer drafts it after G1 |
| 4 | | ticket writer proposes tickets, as vertical slices |
| 5 | Read `issues/` (edit, split, delete freely), then `/factory-approve <f> tickets` | coverage check |
| 6 | | build waves, integration, reviews, validation |
| 7 | Answer when notified: `/factory-decide <f> <your answer, and why>` (any text: quotes and backticks are safe) | logged in `decisions.tsv`, read by every role. Questions a rule or an earlier answer settles never reach you: logged as `auto` |
| 8 | At `STEP: unverified`: prove it, or `/factory-accept-unverified <f> <ids\|ALL> "<why>"` | listed as Known limits |
| 9 | Approve fix tickets when behavior or health finds something | fixes built, re-validated |
| 10 | | health ratchet, then code steward (G5) |
| 11 | At `STEP: pr`: `/pr`, then `scripts/factory/mr.sh <mission>` (add `--draft` for a draft), then `/retro` | metrics printed |

Keep specs to roughly 12 stories or fewer; split anything bigger into two missions.

## 7. STEP codes

| STEP | Who | Means | Do |
|---|---|---|---|
| `paused` | lead | a pause note exists | lead resumes and continues |
| `grill` | you | no spec | `/grill-with-docs`, `/to-spec` |
| `context-sync` | lead | context repos not cloned, or changed in the spec | `context.sh sync <f>` (read-only clones, D99) |
| `investigate` | lead | briefs, answers, a conclusion or a reproduction ticket missing | runs the investigate wave (explorers, then the investigator) |
| `approve-conclusion` | you | the investigation concluded | `/factory-approve <f> conclusion` |
| `handoff` / `report` | you | the fix belongs elsewhere / an exploration is done | send the finding / read the report; the mission ends |
| `contract` | lead | no contract, no critique, or a pending amendment | runs the contract wave |
| `approve` | you | G1 | `/factory-approve <f>` or `/factory-amend` |
| `design` | lead | feature or refactor (or `**Design:** yes`), G1 approved, no `design.md` | runs the designer |
| `approve-design` | you | G1b: `design.md` not approved | read it, `/factory-approve <f> design` |
| `decide` | you | a worker or reviewer asked something | `/factory-decide` |
| `tickets` | lead | no tickets | ticket writer drafts them |
| `approve-tickets` | you | tickets or fix tickets proposed | review `issues/`, `/factory-approve <f> tickets` |
| `coverage` | you | G2: an assertion uncovered or a ticket unjustified | fix `## Covers`, or amend |
| `setup` | you | `FACTORY_TEST_CMD` empty | `factory setup --write` (D102), or fill `.factory/commands.env` yourself; commit |
| `build` | lead | tickets ready | build wave → integrate each patch |
| `review` | lead | integrated tickets | review wave → `collect.sh` |
| `escalate` | you | 3 failed rounds | usually: split the ticket, amend the contract, or rethink the design |
| `blocked` | you | `## Blocked by` can't resolve, a misspelled mission, or the checkout is on another branch | check for cycles; use the name it suggests; `git switch` to the branch it names |
| `validate` | lead | all tickets pass, or fixes built since a failing verdict | validator → `collect.sh` |
| `behavior-fix` | lead | behavior FAIL with findings | ticket writer drafts one fix ticket per finding |
| `behavior-stale` | lead | behavior paths changed after validation | re-validates |
| `unverified` | you | PASS left assertions or bar items unproven | prove, or accept |
| `health` | lead | no health report for the current code | `health.sh check` (no model) |
| `health-fix` | lead | ratchet or steward failed | ticket writer drafts fix tickets |
| `steward` | lead | no steward verdict for the current code | code steward → `collect.sh` |
| `pr` | you | all gates green | `/pr`, `mr.sh`, `/retro` |

## 8. The quality bar (G5)

The codebase is the fuel that brings value to customers, so every mission must leave it **safe, understandable by any human, battle-tested and predictable**. Two layers:

- **Tests that test something (D96):** at integration and in self-check, a ticket's new tests run alone on the code before the change. Feature and bugfix: they must fail there. Maintenance and refactor: they must pass there. A ticket opts out with `## Test on base: skip — <reason>` (a decision, logged); `FACTORY_TEST_ON_BASE=0` turns it off. One extra test run per ticket with tests.
- **Measured (no model):** `health.sh check` compares duplication, large files, deep nesting, debt markers and skipped tests to `.factory/health-baseline.json`. A mission may improve them, never make them worse. Your repo tool (`FACTORY_HEALTH_CMD`) must pass too. Pick its thresholds on **maximum complexity** and **duplicated-code share** first: of 41 deterministic quality metrics in a long-horizon benchmark (SlopCodeBench), those two were the ones that told good and bad code apart; most others barely moved. A justified exception: a human runs `scripts/factory/health.sh baseline` and commits it with the reason.
- **Judged:** the code steward (fresh, on another family than the workers) reads the whole mission diff against `docs/agents/quality-bar.md`. Every `QB-` item gets evidence or a label, and every changed source file gets a three-sentence explanation. A file it can't explain fails the gate: a human wouldn't understand it either.

## 9. Safety: what agents can never do

| Layer | When | What it stops |
|---|---|---|
| **Command guard** (`.pi/extensions/factory-guard.ts`) | Live, on every tool call of the lead and agents | push, force, `--no-verify`, history rewrites, `sudo`, recursive deletes of `/ ~ .. .git`, cluster/cloud/secret-store changes, uploads and remote shells, reading credentials (home folder, `.env`, secrets mounted in a container such as a Kubernetes service account token), publishing, merging, writing to the factory, CI or hooks, any route to `instrument/` from a worker |
| **Patch guard** (`patch-guard.sh`) | Every worker patch, every fix-lane change | changes to the instrument, the factory, CI or hooks; deleted, skipped or focused tests; silenced checks (`eslint-disable`, `@ts-ignore`, `noqa`, …); anything that looks like a secret; paths the contract freezes (`## Frozen paths`, or `src/` for a maintenance mission; tests there stay allowed) |
| **No secrets in the hands** (D100, D101, in the guard) | Every bash call in a factory project | the command runs with credential variables unset: the gateway key (`FACTORY_GATEWAY_KEY_ENV`), the variables Pi's `models.json` names as `apiKey`, `*_TOKEN`, `*_KEY`, `*_SECRET`, `*PASSWORD*`, `*JWT*`, `*_AUTH*`, `*CREDENTIAL*`, `*COOKIE*`, `SSH_AUTH_SOCK`, `GIT_ASKPASS`, `SSH_ASKPASS`, and any variable holding a URL with credentials. A test that needs one keeps it with `FACTORY_TOOL_ENV_KEEP` in the environment that starts Pi (never `commands.env`); the gateway and models.json keys are never kept. No agent reads `auth.json` or `models.json` in Pi's agent folder, `/proc` (beyond cpuinfo, meminfo, loadavg, version, stat) or `ps e` |
| **Approvals** (D101) | next.sh, gate.sh, workflow.sh, the cockpit | an approval line counts only with its `decisions.tsv` row from `/factory-approve`; agents can't write approval lines or `decisions.tsv` |
| **Worker off the network** (D100) | Every tool call from a worker worktree | `curl`, `wget`, package installs, `git fetch/clone/pull`, network code in `python -c`/`node -e`; writes into the shared `node_modules`/`.venv` (the main checkout's, linked in) |
| **CI gate** | Every MR | all of G1–G5, lanes, instrument rule |

**Security model.** Assume anything inside a worker's tools is controlled by an attacker: an agent reads untrusted text all the time (repo files, issues, test output), and one injected line can steer it. So the question is what it can reach, not whether it behaves.

What holds (each rule has a test, D101):
- **The command guard** sees every tool call of the lead and the agents once Pi trusts the project. It matches each command as written, with quotes and backslashes removed, and with git's global options removed: `c''url`, `\curl` and `git -c x=y push` are caught. Network rules apply in command position only, so `grep -rn http src` passes.
- **Workers and bench agents** (`FACTORY_ROLE=worker`) get no network by rule (downloads, installs, git remotes, inline interpreter network code), no writes to the shared dependencies, nothing in `.factory/`, CI, hooks or `instrument/`.
- **Nobody pushes**, the lead included; context clones have no push URL and allow only read-only git.
- **Bash runs without credential variables.** A refused call is logged redacted. The run archive keeps only this checkout's runs, redacted the same way.
- **Approvals need the human's `decisions.tsv` row.**
- **The patch guard** re-checks every patch; MRs are opened by a person.

What doesn't hold (no OS sandbox without root):
- The guard reads command lines. A command built at run time (a variable, base64, a script file the agent wrote, `$'\x63url'`) is not seen.
- The scrub is a rule-level defence, not proof against a determined injection: the harness process's own environment is readable by the same user, and a network route the rules don't name stays open.
- The lead can run `human.sh approve` itself; the decision log records who, so read it.
- Root ignores the context clones' read-only permissions.

Run the factory as a user with only the gateway key it needs, on a machine whose outbound traffic your network already filters. Factory commits are authored by `pi-factory` and committed by you: `git log --author=pi-factory` (GitLab: Repository → Commits, filter by author, or `GET /projects/:id/repository/commits?author=pi-factory`) is what the factory did.

A blocked agent stops and asks; it never looks for another way. Blocks are logged in `.pi-subagents/guard.log`, and patch-guard blocks count as failed rounds in the metrics. The guard loads only once the project is trusted in Pi; the patch guard holds either way. Working on the factory itself in Pi: start Pi with `FACTORY_GUARD=off` (maintainers only, never in a target repo).

## 10. Small changes: the fix lane

```text
/factory-fix <slug> start "<what>"   [--mission <f>]
… make the smallest change, commit it (fix(scope): …) …
/factory-fix <slug> check
```

`check` blocks anything that touches behavior paths or `instrument/`, adds more than 80 lines (`FACTORY_FIX_MAX_LINES`; removed lines are reported, not counted, D76), or fails the patch guard (skips, silenced checks, secrets, deleted tests). Otherwise it runs lint, tests and the extra check, then one fresh reviewer from another family. The verdict lands in `.scratch/light/<slug>/verdicts/code.md`, and the MR gate checks it.

**Before opening the MR** of a mission whose base moved (you merged the target branch in):

```bash
git diff --stat origin/<target> HEAD -- src/          # empty for a characterization mission: no production code changed
git diff origin/<target> HEAD -- package.json         # only test tooling (scripts.test, devDependencies)
```

If the merge left your branch's dependency versions, take the target's `package.json` and lock file and add only the test tooling (`npm pkg set scripts.test=…`, `npm install -D …`).

## 11. Commands you may run yourself

| Command | When |
|---|---|
| `scripts/factory/next.sh <f>` | where is this mission? |
| `scripts/factory/doctor.sh [--quick]` | after install or a model change / before a run |
| `factory setup [--write]` | after onboarding or a change to the test setup: commands found, rehearsed offline, written (D102) |
| `factory report [--full]` | something is wrong and you need help: one redacted text with what a diagnosis needs (D102) |
| `factory tokens <f> [--budget N]` | a provider refused a request on tokens, or a mission costs too much: each run's request sizes and the tool results that fill them (P20) |
| `scripts/factory/gate.sh mission <f>` | the gate CI will run |
| `scripts/factory/metrics.sh <f>` | numbers for the MR |
| `scripts/factory/metrics.sh --all` | every mission and the total: cost per MR, interventions per MR, first pass, scores (D97) |
| `scripts/factory/archive.sh list\|export <f>` | the mission's archived runs (transcripts, briefs, guard refusals), outside the repo (D97) |
| `scripts/factory/score.sh <f> [--dimension x] [--sample n]` | a judge of another family checks archived runs for failure modes in `.factory/scoring/` (D97) |
| `scripts/factory/health.sh metrics` | today's health metrics for the repo |
| `scripts/factory/readiness.sh` | what the repo still lacks for Step 2 |
| `scripts/factory/skills-pin.sh verify\|check-global` | skills drifted or shadowed? |
| `scripts/factory/reset-ticket.sh <f> <ticket> [reason]` | rebuild a ticket from round 1 (verdict, round copies and integration marker removed, one commit) |
| `scripts/factory/self-check.sh <f>` | from a worker's worktree: the checks integration will run (workers run it themselves) |
| `scripts/factory/resolve.sh <f> <ticket> "<question>"` | would this question be auto-answered, and by which rule? |
| `scripts/factory/health.sh baseline` | after setting `FACTORY_LINT_CMD`: records today's lint errors, so only new ones fail |

## 12. Gates and lanes

- **G1** critique present, approved by a human.
- **G2** every assertion covered, every ticket justified; tests configured.
- **G3** each ticket PASS on its latest integration commit, with a generated brief id, recorded by `collect.sh`.
- **G4** behavior PASS, recorded, generated brief, every assertion proven or accepted, and no behavior change since.
- **G5** health report PASS (ratchet + repo tool), steward PASS, recorded, generated brief, every bar item proven or accepted, every changed source file explained, and no source change since.
- **Lanes (MR):** behavior paths touched → a mission must be in the MR. Otherwise a light review is needed. Fix-lane reviews are checked either way. Changing or deleting an instrument case needs `**Amended:**` or `**Withdrawn:**` in the same MR. The `factory:bypass` label skips the gates, visibly.

## 13. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `PREFLIGHT: FAIL … gateway unreachable` | VPN or network | reconnect, `/factory <f>` |
| "blocked by the factory guard" | an agent tried something on the deny-list | read what it needed; if legitimate, you do it by hand (or through the fix lane) |
| `patch blocked` in a verdict | worker touched CI, a test, the factory or a frozen path | recorded as a round; the next build sees the reason |
| Integration fails on lint in code nobody touched | no lint baseline | `scripts/factory/health.sh baseline`, commit `.factory/lint-baseline.txt` |
| Lint baseline misses errors | the lint's output format isn't recognized | prefer a one-line format (`eslint -f unix`, `tsc --pretty false`), or set `FACTORY_LINT_ERROR_RE` |
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
| `STEP: blocked` … "Did you mean" | misspelled mission name | `/factory <the suggested name>` |
| `STEP: blocked` … "is on branch" | the checkout was switched (by you or another agent) | stash foreign changes, `git switch <that branch>`. Other agents work in their own worktree, never in the mission's checkout |
| A worker asks to install a dependency | dependencies not installed in the checkout | install them in the checkout once (`npm ci`); workers get a link (D65). Or set `FACTORY_DEPS_CMD` |
| An `auto` answer in `decisions.tsv` is wrong | a rule matched a question it shouldn't have | change the row's answer, or `/factory-decide` when the worker asks again (a repeat always reaches you) |
| "factory agents start only from a generated workflow file" | the lead tried to call an agent directly (D71) | Esc, then: `Use only subagent({ workflow: "<the WORKFLOW_FILE path>", context: "fresh", async: false }).` |
| 429 on the lead's model in a burst | the lead's quota is per minute (5 on some gateways) | Pi waits and retries; ask for more requests per minute for the lead model |
| "Workflow script timed out after 1800000ms" | pi-subagents' 30-minute default for a wave | `bash scripts/factory/install-pi-config.sh` once (raises it to 2 h); salvage the work: `scripts/factory/integrate.sh <f> <ticket> null` |
| "sent back to review" in `collect.sh` | the reviewer's verdict had no `**Result:**` line | nothing: reviewed again once, not counted as a round |

## 13b. Choose models with data (D98)

Pick models, thinking levels and factory changes on your own tickets, not on public benchmarks or feel.

1. **Build a suite** from tickets the factory did: `scripts/factory/bench.sh add <mission> <ticket> --area <tag>` (difficulty comes from the ticket's rounds; `--difficulty` to override). Mix easy, hard and one escalated ticket, so the suite tells good setups from bad ones. A suite tests one role (`--role`, worker by default).
2. **Run one configuration per run:** a models profile (as `models-profile.mjs` writes) with the roles you test, `bench.sh run default --config gw-maker-1.json --label maker1`. `--case <id> --debug` replays one case and keeps its worktree to look at. `--review` also runs the reviewer on the passes.
3. **Change one thing at a time:** each new profile differs from the default by one variable, a model or a thinking level.
4. **Compare:** `bench.sh compare maker1 maker2 maker1-high` prints the answer first (highest quality, most efficient, lowest cost, with cost per trial; cost recommendations only above a quality floor: within 10 points of the default, or `--min-pass <pct>`), then the breakdown by difficulty and area. The cockpit shows it under **B** (Benchmarks), with a scatter whose axes you pick.
5. **Judge a refactor by changeability:** write two or three follow-up tickets (`bench.sh add-file <issue.md> <mission>`), run `bench.sh probe default --config cheap.json --at <before>` and again `--at <after>`: a cheap model passing more of them on the refactored code is the number that says the refactor helped.

Replays cost tokens: a suite of 10 cases × 3 configurations is 30 worker runs. Run it before changing a model or a brief, not after every mission.

## 14. Where things live

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
docs/agents/factory.md               rules every factory role shares (factory-owned; AGENTS.md only points to it)
docs/agents/quality-bar.md           the bar G5 judges against (repo-owned)
docs/agents/*-<pack>.md              practice pack checklists and bar items (repo-owned)
.factory/health-baseline.json        the ratchet (repo-owned)
instrument/scenarios/                behavior cases (validator only)
```
