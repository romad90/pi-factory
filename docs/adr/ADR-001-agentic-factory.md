# ADR-001 — Agentic factory on Pi

**Revision:** v1.1.0. The codebase is guarded as the team's fuel: code health gate G5 (D49, D50), agents that can't do harm (D51), tickets drafted for you (D52), practice packs keep the factory agnostic (D54). v1.0.0 (after mission 1): records the factory can't overstate (D38–D40), humans decide in one word (D43–D47), small changes stop costing a mission (D41, D42, D48).
**Status:** Accepted
**Date:** 2026-10-10 (v1.0.0 and v1.1.0; first revision 2026-10-07)
**Scope:** The factory on Pi, from a laptop, bots projects first. The team can reuse skills, CI and conventions.
**Target:** Step 2 (Parallel) on Boris Cherny's ladder, solidly and with as little friction as possible.

---

## 1. Context

### Where we actually are

- Pi, with work dispatched to **isolated subagents** (@tintinweb/pi-subagents), several workers in parallel where possible. Not one session doing everything.
- Skills from mattpocock/skills, an older version. A general AGENTS.md plus a specialist one from the bots starter kit.
- No contract before code, reviewers briefed by the lead in its own words, reviewers often on the lead's model, no gate a tired human can't skip.

So the **mechanics of Step 2 are already in place**. What's missing is the **trust layer**: an independent definition of done, unbiased review, enforced gates, and the evidence that the loop catches what you used to catch by reading.

### Inputs to this revision

- **Factory "Missions"** and Factory's research: separate roles with fresh context, a standard of completion written before the work, validators that report, an instrument hidden from implementers ("the wall"), routing models by role.
- **mattpocock/skills v1.3.1** (commit `24fe0ef`): `code-review` (two axes in parallel sub-agents), `to-spec`/`to-tickets`, `tdd` with seams, `retro`, `pr`, `grilling`, `GLOSSARY.md`.
- **pi-subagents (nicobailon) 0.76.1**: one model per agent in its frontmatter, model scope enforcement, workflow scripts with per-child worktrees and a setup hook, a supervisor channel, Herdr integration.
- **Boris Cherny's Steps of AI Adoption** (July 2026), §10 and [`docs/LADDER.md`](../LADDER.md).
- **Mission 1** (a batch bot feature, 9 tickets, MR merged with green CI): its retro is the evidence for D38–D48. See [`docs/case-studies/mission-01.md`](../case-studies/mission-01.md).

---

## 2. Decisions and the reasons behind them

Each decision states its reason. If the reason stops being true, revisit the decision. Superseded decisions are kept, marked, so the history reads straight.

### Structure

**D1. Use upstream skills for every role they cover; pin one version; never fork them.**
*Why:* maintained elsewhere, upgrades are file replacements, our effort goes to the gaps. Enforced by D36.

**D2. Each role runs in a fresh subagent and communicates only through files.**
*Why:* a context that saw the work is biased judging it, and long contexts dilute attention. Files are also the audit trail. Mechanism: D30, D32.

**D3. Missions live in `.scratch/<feature>/` and are committed.** The factory's scripts commit mission state themselves (D46).
*Why:* upstream's local tracker layout, so `to-spec`/`to-tickets` work unchanged; committed so CI can check gates and so worker worktrees (which branch from HEAD) can read spec and tickets.

### Defining done

**D4. The contract is written before the tickets.**
*Why:* if done is defined after the implementation, the implementation defines done. Tests take expected values from the contract, not the code.

**D5. A contract critic attacks the contract before the human approves it** (fresh, other model family, domain checklist).
*Why:* the contract is the highest-leverage artifact; a wrong one makes everything after it converge confidently on the wrong result.

**D6. Traceability both ways:** spec → contract by the critic (judgement), contract ↔ tickets by `coverage.sh` (mechanical).
*Why:* judgement where needed, a script where possible.

**D7. The contract can be amended through a formal path that needs re-approval.**
*Why:* contracts are sometimes wrong; the fix belongs where the error is, not in endless fix rounds on correct code.

### Verifying

**D8. Deterministic checks before any LLM reviewer.** Lint and tests run on every integration (D34) and in CI.
*Why:* cheap and exact; LLM tokens go to what only judgement catches.

**D9. Gates are enforced by GitLab CI on every MR.** `factory:bypass` exists for emergencies, visible and counted.
*Why:* a gate that depends on discipline gets skipped when tired. Requires "Pipelines must succeed".

**D10. Verdicts record their commit; stale behavior and light-lane verdicts are rejected.**
*Why:* a PASS from an earlier commit must not let later code through.

**D11. The lane is chosen automatically from the paths an MR touches** (`.factory/behavior-paths`).
*Why:* no one has to decide, no one can downgrade a behavior change by mistake.

**D12. Validators report and never fix; a fix is a new ticket.**
*Why:* a reviewer that fixes grades its own fix. Backstop: any code change after a verdict makes it stale (D10) or uncovered (D34).

**D13. Judges run on another model family than what they judge** (critic ≠ author; reviewer, review axes, validator ≠ workers). Enforced by D31.
*Why:* a validator is useful where it fails differently; same-family models share blind spots.

### Bot behavior

**D14. The bot test harness is the first mission and ships in the bots starter kit.** Its cases (the instrument) live apart from it (D21).
*Why:* black-box validation needs it; paid once.

**D15. Each behavior case runs N times against a threshold; partial passes are `FLAKY` and fail.**
*Why:* LLM bots are stochastic; flakiness usually means a vague prompt or assertion.

### Scale and cost

**D16. Frontier tickets run in parallel, one isolated worktree each.** Mechanism: D35.
*Why:* parallel agents need isolated workspaces. Core mechanic of Step 2.

**D17. Cost controls:** deterministic checks first, reviews scoped to the diff, stable prompt prefixes, mechanical findings moved to CI by `/retro`.
*Why:* fresh reviewers and fix rounds cost tokens; `/retro` keeps cutting the cost.

**D18. Measure tokens per ticket before asking for more quota.**
*Why:* a request backed by data is a negotiation; an estimate is a guess.

### Orchestration

**D19. ~~Phase 1: the human runs the steps with `next.sh`; phase 2: a Pi runner extension.~~** Superseded by D33: pi-subagents' workflow scripts plus generated orchestration remove the need for a runner extension.

**D20. Escaped bugs go through `/retro` and become a new assertion or a new CI check.**
*Why:* every escaped bug is a gap in the contract or the guardrails.

### The wall and validation quality

**D21. The instrument is hidden from workers.** Behavior cases live in `instrument/`, left out of worker worktrees (D35).
*Why:* once an implementer can see the sample it's judged on, the sample becomes the target. The wall is soft (git history), which is enough for Step 2.

**D22. Exact checks by default; every relaxation named and licensed.**
*Why:* each relaxation is a place wrong behavior can pass; explicit keeps them rare.

**D23. The instrument can grow, never quietly shrink.** Changing or deleting a case needs a contract amendment in the same MR (CI).
*Why:* the standard must not collapse around whatever was built.

**D24. Escalation by model:** a ticket that failed round 2 is rebuilt by `factory-worker-heavy` (frontier). Model choice itself: D31.
*Why:* repeated failure is the signal a task needs more reasoning.

**D25. Behavior verdicts carry findings clustered by root cause; one fix ticket per cluster, written by the human.**
*Why:* direction without leaking cases; one ticket per cause, not per symptom.

### Running Step 2 on a laptop

**D26. Measure outcomes per mission** (`metrics.sh` into every MR).
*Why:* Step 2 is reached when the numbers show the loop catches what reading used to catch.

**D27. Parallelism sized to the laptop:** 4 concurrent children (`parallel.concurrency`), 4 tickets per wave (`FACTORY_MAX_PARALLEL`), a bot port per worktree, sleep inhibited during missions.
*Why:* tests and bot instances run locally; steady beats overloaded.

**D28. A readiness check per repo** (`readiness.sh`).
*Why:* most agent failures come from the environment, not the model.

### This revision: orchestration and enforcement

**D29. One orchestration package: pi-subagents (nicobailon), pinned at 0.76.1. @tintinweb/pi-subagents is removed.**
*Why:* running every subagent on its own model is a hard requirement. pi-subagents layers per-run, frontmatter, per-role settings and default models; enforces a model scope; and shows the live mapping (`/subagents-models`). It also brings worktree setup hooks (D35), a supervisor channel (D37) and Herdr integration. One package only: two orchestration tools confuse the lead. Pinned because it moves fast.

**D30. Factory roles are repo-defined agents** (`.pi/agents/factory/`). Builtins are disabled. Every factory agent: `defaultContext: fresh`, project instructions inherited (AGENTS.md rules reach every role), `inheritSkills: false` with explicit `skills` and `skillPath` to the pinned copy, no agent memory, strict tool lists.
*Why:* the package's builtin `worker`/`oracle`/`advisor` default to forked context (the lead's conversation) and its builtin `reviewer` makes fixes, both against D2 and D12. Memory could carry instrument details past the wall.

**D31. Each factory agent declares its own model in its frontmatter** (`model`, `thinking`). `.pi/settings.json` keeps only package-level guards: builtins off, `modelScope.enforce`, root resolution, and a retry block for shared quotas. Family separation (D13) is checked by `models-lint.mjs`, in CI.
*Why:* every subagent must run on its own model, and the frontmatter is the documented, authoritative place for it. Revised after S0: pi-subagents 0.76.1 only accepts **builtin** names in settings `agentOverrides`; project agents there crash agent discovery ("Builtin override 'factory-…'"). `migrate-models.mjs` moves existing overrides into frontmatter; the lint fails on any `factory-*` left in `agentOverrides`. `fallbackModels` was later removed upstream and stops an agent from launching; the lint fails on it. Models are template-owned: set them once in the template repo, `install-into.sh` propagates them.

**D32. Briefs are generated, never written by the lead.** `brief.sh` renders a per-role template with file paths, a commit, and a `brief-id`, closed by an END OF BRIEF line. Reviewers and validators copy the id into their verdict; the gate recomputes it.
*Why:* a subagent only knows what its task says. A lead summarizing its own reasoning ("I did X because Y") carries its bias into an isolated context. Generated briefs carry paths, not narrative, and the id makes a hand-written dispatch visible at the gate.

**D33. The lead relays; scripts orchestrate.** `/factory <feature>` loops: `next.sh` gives the state as a `STEP:` code; `workflow.sh` generates the exact `workflowScript` for each wave from mission files; the lead passes it verbatim with `context: "fresh"`. Humans own G1, ticket writing, behavior adjudication, escalations and the MR.
*Why:* orchestration that isn't improvised, with no runner extension to build or maintain. The lead model's job shrinks to relaying, which is easy to do correctly.

**D34. A deterministic integration gate between workers and reviewers.** `integrate.sh` applies a worker's patch, runs lint and tests, and commits only if green; a failure is reverted and recorded as a FAIL verdict (counts toward escalation). Each code verdict reviews one integration commit (`state/<ticket>.integrated`).
*Why:* reviewers only ever see committed, green code, so their tokens go to judgement. Recording failures keeps the round count honest.

**D35. Worker worktrees come from pi-subagents; a setup hook hides the instrument.** The hook sparse-checks-out everything but `instrument/` and writes a per-worktree `.env.factory` port (declared synthetic, so not in the patch). pi-subagents reads its config only at user level, so `install-pi-config.sh` installs a shim that delegates to the repo's hook and does nothing in other repos.
*Why:* the package's worktree lifecycle (clean HEAD, patch capture, cleanup) replaces our `worktree.sh`. Tracked files can't be declared synthetic, but a sparse checkout keeps them out of the tree without appearing as deletions in the patch (tested).

**D36. mattpocock/skills v1.3.1 is vendored in `.pi/skills/` and enforced by checksum.** `skills-pin.sh verify` (CI) checks every pinned file against `skills.sha256`, the declared version, shadow copies in other project skill locations, and markdown under `.agents/`. `check-global` (local) warns about machine-wide copies that differ.
*Why:* "use v1.3.1" must be checkable, not a convention. `.pi/skills/` because pi-subagents resolves project skills there first and doesn't list `.agents/skills/` for subagents, and because it scans legacy `.agents/**/*.md` as agent definitions: skills there would register as agents.

**D37. Escalations travel through the supervisor channel.** A child that needs a decision asks the parent (`contact_supervisor`); the lead relays the question to the human verbatim.
*Why:* a worker guessing a product decision is a defect waiting for review; asking is cheaper.

### v1.0.0: records that can't overstate, humans in one word

Mission 1 worked end to end, and showed where the factory could still lie or stall. Each decision below names the evidence.

**D38. Rounds come from history, never from the agent.** `collect.sh` archives every verdict as `<stem>.r<N>.md` and writes the round itself. Deterministic failures (an integration that fails, a worker run without a patch) are rounds too. The gate rejects a verdict that wasn't recorded or changed afterwards.
*Why:* a ticket showed "round 1" after two failed runs and an escalation, and metrics reported a 100% first-pass rate that wasn't true. A worker run without a patch didn't count, so escalation needed a hand-written verdict.

**D39. The factory, not the agent, reports facts about the run.** The model in a verdict is the one configured for the role. The build wave returns each ticket's patch path; `locate-patch.sh` is the fallback.
*Why:* verdicts claimed a model that wasn't in use (models guess who they are), and the lead searched temp folders for patches by hand.

**D40. Evidence or label.** Every assertion in a verdict is `PASS — <evidence>`, `FAIL`, or `UNVERIFIED — <why>`; a PASS without evidence is unverified. G4 blocks unverified behavior until it is proven or a human accepts it (`/factory-accept-unverified`), and the MR lists it under Known limits.
*Why:* the mission reported every behavior assertion as passed while no harness existed. "Tests pass" was standing in for behavior evidence.

**D41. A fix lane for small changes.** `/factory-fix`: the smallest change, a blast-radius check (behavior paths and the instrument are blocked, a line limit), lint/tests/extra check, one fresh reviewer from another family. The gate checks fix-lane reviews in either lane.
*Why:* a three-line chart fix needed either the full ticket ceremony or a commit outside any gate; in mission 1 it went outside.

**D42. A behavior verdict goes stale only when behavior changes** (a path in `.factory/behavior-paths`, or the instrument). Without patterns, any code change counts.
*Why:* a README or deployment tweak forced a full behavior revalidation, which costs scarce quota.

**D43. Human gates are one command.** `/factory-approve`, `/factory-decide`, `/factory-amend`, `/factory-accept-unverified` write the line, log it in `.scratch/<feature>/decisions.tsv` and checkpoint. Workers, reviewers, validators and the contract author read the log. Rows stay `unreviewed` until a human promotes them to the spec or an ADR.
*Why:* decisions lived only in chat, approvals were typed into `spec.md` by hand, and a stale supervisor request kept showing after it was answered.

**D44. No integration without tests.** `next.sh` stops at `STEP: setup` and `integrate.sh` refuses while `FACTORY_TEST_CMD` is empty. `FACTORY_EXTRA_CMD` adds a third check, such as a chart lint the CI runs.
*Why:* an empty `commands.env` would have let integration commit without any check, and a chart lint failure was only found in CI.

**D45. The factory calls you; you don't watch it.** Every human `STEP` notifies (macOS, `notify-send`, or `FACTORY_NOTIFY_CMD`). `/factory-pause` writes where it stopped and the open question; `/factory` in a new session resumes. The lead pauses itself after a wave when its context is above about 70%.
*Why:* long waves were watched by hand; a VPN cut and a lead stuck in a repetition loop each forced a restart from memory.

**D46. Pre-flight, and checkpoints are automatic.** `/factory` starts with `doctor.sh --quick` (repo root, node, tests configured, clean tree, models, gateway reachable). Every script that changes mission state commits it.
*Why:* a dropped VPN produced seven connection errors in a row instead of one message, and `checkpoint.sh` was run by hand about ten times.

**D47. Irreversible choices never default.** Deletes, secrets, production behavior and the contract itself: a worker stops with `DECISION NEEDED`, the lead records the question (`STEP: decide`), a human answers. A timeout is not a yes. Reversible code choices proceed and are reported.
*Why:* a worker timed out on a question and proceeded with the option the spec had ruled out.

**D48. The factory is installed through its own MR.** `install-into.sh` commits on `chore/install-pi-factory-<version>`.
*Why:* the first feature MR carried 193 files, mostly tooling, which hides the feature from its reviewer.

### v1.1.0: the codebase as fuel, agents that can't do harm

The codebase is what the team uses to bring value to customers. It must stay safe, understandable by any human, battle-tested and predictable, and agents with bash must not be able to damage it or anything around it.

**D49. A code steward judges every mission before it merges (G5).** `factory-code-steward` (fresh, on another family than the workers) reads the **whole mission diff** (`mission_base..HEAD`) against a written, repo-owned quality bar (`docs/agents/quality-bar.md`): safe, understandable, battle-tested, predictable, as `QB-` items. Every item gets evidence or a label (D40), every changed source file gets a three-sentence explanation, and the gate fails on a file it could not explain. It reports; findings become fix tickets.
*Why:* per-ticket reviews see small diffs; erosion happens across tickets (the same logic three times, a clever abstraction, an untested failure path). "Clarity over cleverness" needs an owner and a written bar, or it is everyone's opinion and nobody's job. A file a fresh model can't explain is a file a newcomer won't understand.

**D50. Measured health first, with a ratchet.** `health.sh` measures duplication, large files, deep nesting, debt markers and skipped tests over the repo's source files, and runs the repo's own tool (`FACTORY_HEALTH_CMD`). The metrics may improve, never get worse than `.factory/health-baseline.json`; a justified exception is a human committing a new baseline with the reason. It runs before the steward, which gets the report as evidence. G5 verdicts go stale only when source files change.
*Why:* deterministic checks before any LLM (D8). A ratchet improves a codebase without a big-bang cleanup: pre-existing debt is not the mission's fault, but no mission may add to it.

**D51. Two guards: live commands and integrated patches.** The command guard (`.pi/extensions/factory-guard.ts`, rules in `guard-rules.mjs`, unit-tested) blocks dangerous tool calls by the lead and agents: pushes and history rewrites, `--no-verify`, privilege, recursive deletes of `/ ~ .. .git`, cluster/cloud/secret-store changes, uploads and remote shells, credential reads, publishing and merging, writes to the factory, CI or hooks, and routes to the instrument from a worker. The patch guard (`patch-guard.sh`) rejects, on every worker patch, changes to the instrument, the factory, CI or hooks, deleted/skipped/focused tests, silenced checks and secret-looking strings; a block is a recorded round. The fix lane applies it to human changes too, except paths.
*Why:* agents have bash on a laptop with your identity. A prompt saying "don't" is not a control. The live guard stops harm before it happens; the patch guard is deterministic and holds even if the extension doesn't load (it needs a trusted project; loading in pi-subagents children is to be confirmed). Neither is a sandbox: that is S5, the bar for Step 3.

**D52. Tickets are drafted by an agent and approved by you; size routes the worker.** `factory-ticket-writer` writes the tickets from the approved contract, and fix tickets from behavior or health findings (one per root cause). Nothing builds until a human runs `/factory-approve <feature> tickets`. A `**Size:** L` ticket goes straight to the heavy worker.
*Why:* in mission 1, tickets were written by hand in the main session and fixed by hand afterwards (a missing ticket, missing `## Covers`), and the core ticket failed twice on the efficient worker. Approving a plan is cheap; writing it is not.

**D53. A failing behavior verdict is re-validated once fixes are built.** If code changed since a failing behavior verdict, the next step is `validate`, not new fix tickets.
*Why:* without it, the mission asked for fix tickets for findings that the built fixes had already addressed.

### v1.1.0 (cont.): agnostic machinery, owned content

**D54. Domain practices arrive as practice packs: content, never code.** A pack (`packs/<name>/`) is a contract checklist for the author and critic (G1) and `QB-<PACK>-NN` items for the steward (G5), installed with `install-into.sh --pack <name>` and repo-owned afterwards. Briefs read every `contract-checklist-*.md` and `quality-bar-*.md` present. Packs: `api` (Stripe-inspired; **Public** items only for third-party APIs), `batch`. A pack is a shape (how the software runs, fails and is proven done), not a label: a batch bot is `batch`. A new pack is written from the first real mission that needs it, with both files; a thin pack looks covered and isn't, so the conversational `bot` checklist was dropped before release. Planned: `front-end`, `llm-app`.

**D55. Models are set once per machine.** Model ids, thinking levels, scope and families are the same across your repos and machine-specific, so they live in a profile outside any repo (`~/.pi-factory/models.json`), captured from a configured repo and applied by `install-into.sh`; the template keeps placeholders, and `models-lint` still decides.

**D56. A monorepo folder is a project of its own.** Where each folder owns a domain and its CI, the factory installs into that folder, never at the monorepo root (that would impose it on every team). Every diff is `--relative` to the project; worker patches are rewritten to project paths before the patch guard, and a patch reaching outside the project is a blocked round (git apply would otherwise drop those files silently); patches apply from the root with `--directory`. pi-subagents resolves the nearest `.pi` (`projectRootResolution: nearest`); the worktree hook hides `<project>/instrument/` and the command guard finds the project from the agent's folder, so the wall holds. CI jobs are named after the project and run only when it changed, from its folder. A fake two-project monorepo runs the whole mission test and checks the sibling is untouched.
*Why:* the factory builds bots, APIs, front ends, in any language; baking one domain into scripts or roles would make it neither agnostic nor lean. Good practices still matter most on a blank page, where conventions cost nothing; on an existing code base, consistency with it beats any ideal, so packs are pruned before use, not enforced blindly. Company taste stays in `AGENTS.md`.

**Not adopted (yet): Pi Durable.** Earendil's experimental framework for durable, multi-client agent applications (checkpointed tasks, execution environments per conversation, steering from several surfaces). The factory's durability already comes from files and git, and a TypeScript runner would be a second architecture on an unstable API. It is the candidate for the Step 3 runner (roadmap), with the scripts staying the brain.

---

## 3. Flow

```
HUMAN, main session       /grill-with-docs → /to-spec → .scratch/<f>/spec.md
                                                                       D3, D4
/factory <f>   pre-flight (doctor.sh --quick), then the lead loop:     D46
               next.sh → act → repeat; scripts checkpoint themselves
  contract     workflow.sh contract → author, then critic             D5, D32
               (fresh; critic on another family)                      D13, D31
  ── G1, HUMAN: /factory-approve  (or /factory-amend "<change>") ────── D7, D43
  tickets      workflow.sh tickets → ticket writer (fresh)            D52
  ── HUMAN: /factory-approve <f> tickets ───────────────────────────── D52
  ── G2: coverage.sh clean;  FACTORY_TEST_CMD set ─────────────────── D6, D44
  build        workflow.sh build-wave                                 D33
               ≤4 factory-workers in parallel, own worktrees,         D16, D27
               instrument hidden, own port; heavy model after round 2 D21, D24, D35
               → patch path returned → integrate.sh per patch:        D39
                 patch guard, lint, tests, extra → commit, or a round D8, D34, D38, D51
               no patch → record-no-patch.sh (a round)                D38
               DECISION NEEDED → human.sh ask → HUMAN /factory-decide D43, D47
  review       workflow.sh review-wave → fresh reviewers, other      D2, D13
               family; code-review axes dispatched to review-axis
               → collect.sh: round from history, configured model     D38, D39
  ── G3: every ticket PASS on its latest integration ──────────────── D34
  validate     workflow.sh validate → validator in main checkout,     D14, D15
               holds the instrument → collect.sh                      D22, D23, D25
  ── G4: behavior PASS, evidence or accepted label, behavior fresh ── D10, D40, D42
               (findings → ticket writer drafts fix tickets → approve) D25, D52, D53
  health       health.sh check: ratchet + repo tool, no model         D50
  steward      workflow.sh steward → code steward, whole mission diff  D49
               vs quality bar → collect.sh                            D38, D39
  ── G5: health PASS, bar met or accepted, every file explained ───── D49, D50
  pr           metrics.sh → HUMAN: /pr, MR, /retro                    D20, D26
Always         command guard on every tool call (lead and agents)     D51
CI             factory-config (skills pin, models), factory-gate      D9, D31, D36
               (G1–G5, lanes, briefs, records, instrument rule)       D11, D23, D38
```

Every human STEP notifies you (D45). `/factory-pause` and `/factory` resume across sessions.

**Fix lane** (small, no behavior path): `/factory-fix <slug> start "<what>"`, make and commit the change, `/factory-fix <slug> check` → blast radius, checks, one fresh reviewer → `.scratch/light/<slug>/` (D41).

**Light lane** (no behavior path touched, chosen by CI): `/factory-light <slug> <base>`, one fresh reviewer → `.scratch/light/<slug>/verdicts/code.md`.

---

## 4. Artifacts

| Artifact | Path |
|---|---|
| Spec + contract, critique | `.scratch/<f>/spec.md`, `contract-critique.md` |
| Tickets | `.scratch/<f>/issues/NN-<slug>.md` |
| Integration markers, logs | `.scratch/<f>/state/<ticket>.integrated`, `logs/` |
| Verdicts and their history | `.scratch/<f>/verdicts/<ticket>-code.md` + `<ticket>-code.r<N>.md`, `behavior.md` + `behavior.r<N>.md`; light: `.scratch/light/<slug>/verdicts/code.md` |
| Human decisions | `.scratch/<f>/decisions.tsv`; open question `state/open-question.md`; amendments `amendments/` |
| Pause note | `.scratch/<f>/state/PAUSED.md` |
| Fix lane | `.scratch/light/<slug>/request.md`, `blast-radius.md`, `verdicts/` |
| Code health | `.scratch/<f>/health/report.md`, `verdicts/health.md`; bar `docs/agents/quality-bar.md`; ratchet `.factory/health-baseline.json` |
| Guards | `.pi/extensions/factory-guard.ts`, `scripts/factory/guard-rules.mjs`, `scripts/factory/patch-guard.sh`; blocks logged in `.pi-subagents/guard.log` |
| Instrument (validator only) | `instrument/scenarios/`; raw results `instrument/results/` (ignored) |
| Factory agents | `.pi/agents/factory/*.md` |
| Models per role | `.pi/agents/factory/*.md` frontmatter |
| Scope, builtins off | `.pi/settings.json` (`subagents`) |
| Model families + rules | `.factory/model-families.json` |
| Brief templates | `.factory/briefs/<role>.md` |
| Pinned skills | `.pi/skills/`; pin in `.factory/skills-pin/` |
| Lead playbooks and one-word gates | `.pi/prompts/factory*.md` |
| Integration commands, gateway URL | `.factory/commands.env` |
| CI jobs (included) | `.factory/ci/factory.gitlab-ci.yml` |
| Lane rule | `.factory/behavior-paths` |

---

## 5. Gates

| Gate | Condition | Where |
|---|---|---|
| G1 | Critique exists; human approved (`/factory-approve`, dated line) | `gate.sh`, `next.sh` |
| G2 | Every assertion covered; tickets justified; no unknown IDs | `coverage.sh` |
| G3 | Each ticket PASS, on its latest integration commit, with a generated brief id, recorded by `collect.sh` | `gate.sh` |
| G4 | Behavior PASS, recorded, with a generated brief id; every assertion proven or accepted unverified; no behavior change since | `gate.sh` |
| G5 | Health report PASS (ratchet, repo tool); steward PASS, recorded, generated brief, every `QB-` item proven or accepted, every changed source file explained; no source change since | `gate.sh` |
| Lane | Behavior paths → mission required; else fresh light verdict; fix-lane verdicts checked in either lane | `gate.sh mr` |
| Instrument | Changed/removed cases need a contract amendment | `gate.sh mr` |
| Config | Skills match v1.3.1 pin, no shadows; models per role, families separated | `factory-config` |

**"Pipelines must succeed" must be enabled**, or every gate is advisory.

---

## 6. Roles

| Role | Agent | Skills | Tools | Model (settings) |
|---|---|---|---|---|
| Clarifier, spec | human + main session | grill-with-docs, to-spec | — | session model |
| Ticket writer | factory-ticket-writer | ticket-writer | read, write (issues only) | frontier, any family |
| Contract author | factory-contract-author | contract | read, write, edit | frontier, family A |
| Contract critic | factory-contract-critic | contract-critic | read, write (critique only) | frontier, family ≠ A |
| Worker | factory-worker | tdd, codebase-design | all builtins | efficient, family C |
| Escalated worker | factory-worker-heavy | tdd, codebase-design | all builtins | frontier |
| Reviewer | factory-reviewer | code-review | read, bash, write (verdict), subagent | frontier, family ∉ workers |
| Review axis | factory-review-axis | — | read, bash | frontier, family ∉ workers |
| Validator | factory-validator | verify-behavior | read, bash, write | frontier, family ∉ workers |
| Code steward | factory-code-steward | code-steward | read, bash, write (verdict) | frontier, family ∉ workers |
| Lead | main session, `/factory` | bundled pi-subagents skill | subagent | session model |

---

## 7. Skill inventory

`.factory/skills-pin/UPSTREAM.md` has the full list, roles and upgrade procedure.

- **Upstream v1.3.1 (18):** grilling, grill-with-docs, grill-me, domain-modeling, codebase-design, to-spec, to-tickets, setup-matt-pocock-skills, tdd, code-review, diagnosing-bugs, pr, retro, improve-codebase-architecture, writing-for-agents, handoff, teach, setup-pre-commit.
- **Local:** contract, contract-critic, verify-behavior, ticket-writer, code-steward.
- **Not vendored:** implement, implement-spec (orchestration is D33), and the rest.

---

## 8. Consequences

### Positive

- **Unbiased dispatch is structural:** fresh context by agent default, generated briefs, ids checked at the gate (D30, D32).
- **Every subagent on its own model,** families separated and linted in CI (D31).
- **Records can't overstate:** rounds, models and evidence are written by scripts (D38–D40).
- **Code health has an owner and a floor:** a written bar, a ratchet, a steward on another family (D49, D50).
- **Agents can't push, publish, touch production or read credentials,** and unsafe patches never land (D51).
- **Less friction:** one command per mission (`/factory`); humans only at G1, tickets, behavior adjudication, escalations and the MR (D33). No runner extension to build.
- **Reviewers see only green, committed code** (D34).
- **v1.3.1 is enforced, not hoped for** (D36).
- **Gates hold regardless of discipline** (D9, D10).

### Remaining weaknesses

| Weakness | Status | Mitigation |
|---|---|---|
| Built against docs; workflow API details unverified in a live Pi | **Open until S0** | S0 dry run on a toy repo; field names to check are listed in §11 |
| Tokens and time | Reduced | D8, D17, D18, D34; heavy model only after failure (D24) |
| Contract as single point of failure | Much smaller | D5, D6, D7, D20 |
| The lead could still alter a brief | Detected, not prevented | Brief id at the gate; END OF BRIEF marker; children flag extra text |
| The wall is soft | Firmer since D51 | Command guard blocks routes to `instrument/` from a worker worktree; patch guard rejects changes to it; separate repo is the hard version |
| The command guard is a deny-list, loaded only in a trusted project | Accepted for Step 2 | Patch guard and CI stand behind it (D51); OS sandbox is the Step 3 bar (S5) |
| The steward's clarity judgement is a model's | Reduced | Ratchet and "explain every file" are mechanical; other family; evidence per `QB-` item (D49, D50) |
| Package moves fast | Pinned | Upgrade like skills: read changelog, rerun S0 |
| Bot harness missing | One-time cost | First mission (D14) |

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| "Pipelines must succeed" off | S0 checklist |
| pi-subagents result shape differs from what `workflow.sh` returns (e.g. where the patch path is) | The wave returns `patch` from `artifactPaths`/handoff; `locate-patch.sh` falls back; `record-no-patch.sh` makes a miss a recorded round (D39) |
| Skills under `.agents/` registered as agents | They live in `.pi/skills/`; `skills-pin.sh verify` fails on markdown under `.agents/` |
| code-review axes fail because builtins are disabled | Reviewer dispatches axes to `factory-review-axis` (repo agent, fresh) |
| Model ids not available on the gateway, or a model rejects a thinking level | `models-lint` + `/subagents-models` at S0; pre-flight before each run (D46); see the cheat sheet's model notes |
| Node missing on a runner | CI installs it; locally Pi brings it |
| Mission state not committed before a wave | Scripts checkpoint themselves (D46) |
| Laptop sleeps mid-mission | `caffeinate`/`systemd-inhibit`; background runs survive only while the machine is up |

---

## 10. Where we are on Boris Cherny's ladder

Steps: **1 Assisted** (one agent, you hold the context), **2 Parallel** (~10 agents, AI writes and humans verify), **3 Supervised autonomy** (agents delegate to agents, humans supervise outcomes and exceptions), **4 AI-native** (AI decides what to work on).

**Today (v1.0.0): Step 2 mechanics with the trust layer, 1 mission of 4 run.** Mission 1 went from grill to merged MR through the factory. v1.0.0 makes its records trustworthy. What remains is evidence: three more missions, with parallel waves. The running log is [`docs/LADDER.md`](../LADDER.md).

| Step 2 ingredient | Status |
|---|---|
| Agents in isolated worktrees, in parallel | In use; now with the instrument hidden and ports (D35) |
| Self-verification loop you trust | Built: contract, critic, integration gate, fresh reviewers, validator, CI (D4–D13, D32–D34) |
| Automated review on another model | Built and enforced (D13, D31) |
| No permission prompts stalling agents | Not seen in mission 1; dangerous commands now blocked by the guard, not prompted (D51) |
| Code health held across missions | Built: G5 ratchet + code steward (D49, D50) |
| You review final diffs, not every step | Verdicts + metrics in every MR (D26) |

**Step 2 is declared when**, over 4 missions: 3–4 tickets per wave as routine; MRs approved from verdicts and metrics with spot checks only; first-pass review rate and escaped bugs stable or improving; zero unexplained bypasses.

**Toward Step 3 (later, from the laptop):** the pieces are now in the same package: nested delegation, durable missions and schedules, the supervisor channel, Herdr integration. Triggered work (ticket → mission) waits until Step 2 is declared.

---

## 11. Path to Step 2

| Move | What | Exit |
|---|---|---|
| **S0: Set up and dry-run** (done) | Install pi-subagents 0.76.1, remove tintinweb; `install-pi-config.sh`; fill `.pi/settings.json` models and `commands.env`; `/setup-matt-pocock-skills` (local markdown tracker); paste `AGENTS.factory.md`; `doctor.sh` green; in Pi: `/subagents-doctor`, `/subagents-models`, list agents (only `factory-*`). Dry-run `/factory` on a toy mission with one ticket. | One toy ticket goes build → integrate → review → PASS. Any mismatch in workflow fields or patch location fixed in `workflow.sh`/playbook |
| **S1: First real mission** (done: mission 1) | `/factory` on a small bots feature; behavior in interim mode (no harness) | One MR merged with metrics |
| **S2: Behavior** | Harness as a mission; instrument; `behavior-replay` in CI | G4 passed with the wall in place |
| **S3: Evidence** | 4 missions, parallel waves | §10 criteria met → Step 2 declared |

**Checks for the S0 dry run** (documented behavior I couldn't execute here): `runs.run`/`runs.all` accept `{ key, agent, task, worktree }`; results expose `output` and `artifactPaths`; where the worker's patch file sits in the handoff manifest; the setup hook runs for `worktree: true` children; a reviewer can spawn `factory-review-axis` children (depth 2).

**Deliberately deferred:** triggered automations, scheduled runs, separate instrument repo, GitLab issues as tracker, team rollout on OpenCode.

---

## 12. Metrics

`metrics.sh <feature>` per mission: intent, assertions, amendments, tickets and fix tickets, first-pass review rate, review and behavior rounds, cycle time, tokens, models. Across missions: those plus escaped bugs and bypasses. They are the evidence for Step 2 and the data for quota discussions.

---

## 13. Open questions

1. ~~Which models and families does the gateway offer?~~ Settled at S0: families in `.factory/model-families.json`.
2. Does pi-subagents' `permissions` config need an allowlist so parallel workers never stall on prompts?
3. Harness: local instance or preview environment? Which tools are mocked?
4. Team rollout: OpenCode reads skills from its own locations. Mirror `.pi/skills/` for them, or move the team to Pi?
