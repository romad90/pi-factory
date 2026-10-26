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

**D56. A monorepo folder is a project of its own.** Where each folder owns a domain and its CI, the factory installs into that folder, never at the monorepo root (that would impose it on every team). Every diff is `--relative` to the project; worker patches are rewritten to project paths before the patch guard, and a patch reaching outside the project is a blocked round (git apply would otherwise drop those files silently); patches apply from the root with `--directory`. pi-subagents resolves the nearest `.pi` (`projectRootResolution: nearest`); the worktree hook hides `<project>/instrument/` and the command guard finds the project from the agent's folder, so the wall holds. CI jobs are named after the project and run only when it changed, from its folder. Skills and docs say "repo root"; a note in `AGENTS.md` tells every agent that means the project folder, so a glossary or ADR never lands at the monorepo root. A fake two-project monorepo runs the whole mission test and checks the sibling is untouched. The patch guard reads both sides of every file with git's quoting decoded, so a rename out of the instrument, a quoted or spaced path, or a new symbolic link is blocked like any other unsafe change (D51).

**D57. Gates in a child pipeline.** A monorepo often starts each project's CI as a child pipeline. There, `CI_PIPELINE_SOURCE` is `parent_pipeline`, the merge request's variables are not passed down, and a red child does not fail the parent unless the trigger job uses `strategy: depend`: the gates would never start, or never block. `install-into.sh --ci child` writes rules for the child pipeline; the parent's trigger job passes `FACTORY_MR_TARGET` and `FACTORY_MR_LABELS` and waits with `strategy: depend`, so the gates run only for merge requests and their result blocks the merge.

**D58. A provider error is not a round.** A worker stopped by the model provider (rate limit, quota, 5xx, overload, timeout) never worked on its ticket. Counting it as a failed round (D38) burned three rounds per ticket in two minutes on a 10-request-per-minute gateway and escalated tickets whose code was never written. The lead records it with `record-no-patch.sh --provider`: no verdict, the mission pauses with the error, and resumes once the provider is back. The wave size can live in `.factory/commands.env` (`FACTORY_MAX_PARALLEL`), so a low quota is set once per project.

**D59. Probe the gateway, not only the config.** Every pre-flight passed while waves failed on the gateway: a model not served to the key (403), a thinking level refused (400), a provider rejecting a user turn after a tool result (400), a quota far below what a worker needs (429). `models-probe.mjs` asks the gateway for its model list, replays a tool turn with each agent's model and thinking level, and reads the quota headers. It spends a few requests, so it runs on `doctor.sh` (full) and writes a stamp; the pre-flight only checks the stamp still matches the agents' models. The pre-flight also fails when `.scratch/` is git-ignored, since mission state must be committed (D3).

**D60. The worker's worktree is the patch of last resort.** In a scripted workflow, pi-subagents 0.76.1 mentions the patch only in the run's text output, so the build wave returned `null` and three rounds of a working harness were recorded as "no patch". The lead was told to run `locate-patch.sh` first and didn't. Now `integrate.sh` runs it itself when given `null`, and `locate-patch.sh` falls back to the worktree pi-subagents keeps per run (branch `pi-subagents/<ticket>-…`, created after the wave): it rebuilds the patch from the newest one against its merge base. A worker run is lost only when its worktree has no change.

**D61. A contract can freeze paths.** In mission 2 (maintenance: characterize, document, change nothing), a docs ticket moved a `return` out of a `finally` in `src/`; review caught it after integration and it took a revert. "Don't touch the code" lived only in prose. Now the spec may list `## Frozen paths` (`dir/` prefixes or globs, `- none` to clear), and a mission with `**Intent:** maintenance` freezes `src/` (`FACTORY_FROZEN_MAINTENANCE`) when it lists none. `integrate.sh` passes the mission to the patch guard, which refuses any change there before the patch is applied: a failed round with the reason, like any other block. Test files under a frozen path stay allowed, since characterization tests often live next to the code. The worker brief lists the frozen paths.

**D62. Lint fails only on new errors.** The team lint failed on legacy `src/` that the mission was not allowed to change; workers didn't know which lint ran, asked twice, then silenced checks three rounds in a row. Now `health.sh baseline` also records the lint errors the code has (`.factory/lint-baseline.txt`, one key per error: file and message, no line numbers, so moved lines stay known), and integration, the fix lane and the G5 health check fail only on errors not in it. A lint run that fails without a recognizable error line still fails: nothing proves it is old. The worker brief carries `FACTORY_LINT_CMD`, `FACTORY_TEST_CMD` and how to fix the common lint errors in tests without silencing them.

**D63. A ticket is reset by a script.** Resetting a ticket by hand took three tries: its round comes from the verdict's `.rN` copies, from the header when none is left, and an integrated ticket also keeps `state/<ticket>.integrated`. `reset-ticket.sh <mission> <ticket> [reason]` removes all three, logs the reset in `decisions.tsv` and commits; the next build is round 1. Integrated code stays in git: revert it first if it must go.

**D64. AGENTS.md stays yours; the factory's rules live in their own file.** The factory used to append about 420 words of rules to the target's `AGENTS.md`. That file is in every agent's context (subagents inherit it), so every call paid for every role's rules, and the briefs asked to read `AGENTS.md` again on top. Teams also want `AGENTS.md` general, for every tool and every developer, not only the factory. Now the shared rules are `docs/agents/factory.md`, owned by the factory and replaced on upgrade; role rules stay in the role files and briefs; `AGENTS.md` gets a two-line pointer; briefs name `docs/agents/factory.md` instead of `AGENTS.md`. An install that finds the old full section leaves it alone and says how to replace it. The shared rule on expected values now depends on the spec's intent: from the `Then` line in a feature or bugfix mission, from running the current code in a maintenance mission (mission 2's first harness asserted values from the contract that the code never produced).
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


**D65. Every worker worktree has the installed dependencies.** A fresh worktree has no `node_modules`: in mission 2 workers asked to install, installed by hand, or wrote tests they couldn't run (retro 35, 41). The worktree hook now links the checkout's dependency folders (`FACTORY_DEPS_LINKS`, default `node_modules .venv`; the project's and the repo root's in a monorepo), or runs `FACTORY_DEPS_CMD` when a team prefers an isolated install. Links are declared synthetic, and `locate-patch.sh` leaves them out: a link escapes a `node_modules/` ignore rule, and the patch guard refuses links. Sharing one install is safe because no patch may change `package.json` or a lock file.

**D66. A worker checks its own work before handing it over.** Integration ran the checks; workers found out a round later, and a round replays a whole worker run. `self-check.sh <mission>` runs what integration runs, from the worktree: the patch guard on the change (through a temporary index, so the worker's own index is untouched and the hidden instrument is not a deletion), lint against the baseline, tests and the extra check. The brief asks for `SELF-CHECK: PASS` before handover. The brief also puts the ticket and the commit last: every worker of a mission then sends the same prompt prefix, which a provider's prompt cache can reuse.

**D67. The right mission, on the right branch.** `/factory <typo>` started a pre-flight on a mission that didn't exist, and another agent switched the checkout's branch mid-mission (retro 38, 40). `next.sh` and `doctor.sh --quick <mission>` now refuse a missing mission whose name is close to an existing one, with the closest name, and refuse a checkout whose `HEAD` doesn't contain the mission's latest state on any local branch, naming that branch. No state is stored: the check reads git.

**D68. Human text never goes through the shell.** The lead built `human.sh decide <m> "<answer>" "<why>"`; backticks inside double quotes ran as commands, and the split between answer and why was guessed. `human.sh ask` and `decide` take `--stdin`, and the prompts pass the text in a quoted heredoc. The answer and the why are one field: the split had never been used.

**D69. A format slip is not a failed round.** A verdict without a `**Result:** PASS|FAIL` line was counted as a failed round and fixed by hand. `collect.sh` now moves it to `state/<ticket>.invalid-verdict.md` and the ticket goes back to review, once; a second slip on the same ticket counts.

**D70. Settled questions are answered without the human.** Most of mission 2's questions had an answer already: a factory rule, or the human's answer to the same question earlier. `resolve.sh` answers those, by exact rules only: dependencies, silencing a check, changing the checks, changing a frozen path, and a question asked before word for word. Anything about production, data, secrets or the contract always goes to the human. Auto-answers are logged as `auto` in `decisions.tsv` (unreviewed) and counted apart in `metrics.sh`; the same question after an auto-answer goes to the human, and from the third question on a ticket the question suggests shrinking or resetting it.

**D71. The lead can only start agents from a workflow file.** On resuming mission 2, the lead called an agent directly instead of passing the `WORKFLOW_FILE` (pi-subagents failed with "Cannot read properties of undefined (reading 'slice')"), retried three times, deleted the generated workflow files and started reading the factory's scripts. The command guard now refuses any `subagent` call that is not `{ workflow: "<.scratch/…/*.js>", context, async }` (status and list actions stay allowed), and any `rm` under `.scratch/`: workflow files and verdicts are the mission's record, and the scripts change them. The rule is enforced by a script, not by the model reading its prompt.

**D72. A wave may run two hours, and a timed-out wave is salvaged.** pi-subagents stops a foreground workflow after its config `timeoutMs`, 30 minutes by default. The first run of ticket 05 on a stronger model with high thinking hit it after 51 turns, with its work still in the worktree. `install-pi-config.sh` now raises `timeoutMs` to 2 hours (never lowers it); the worker's turn budget remains the real cap. When a wave still times out, the lead runs `integrate.sh <mission> <ticket> null` for each of its tickets: the patch is rebuilt from the worktree (D60) and checked like any other, so the work is not lost and no tokens are spent.

**D73. Every self-check saves a draft patch that outlives the worktree.** Salvaging a timed-out wave from its worktree (D72) assumes the worktree is still there; pi-subagents may already have removed it. Each run of `self-check.sh` in a worker's worktree now writes the change as a draft patch in the repository's shared git folder (`<git-common-dir>/pi-factory/drafts/<mission>/<ticket>.patch`): shared by every worktree, never committed, and kept after the worktree is gone. `locate-patch.sh` falls back to it after the worktree, only if it is newer than the wave, and a successful integration deletes it. The draft is as good as the last self-check: the worker saves progress by checking its work, nothing else to remember.

**D74. The lead acts on the `STEP:` line only, and a patch already in the branch is not a crash.** With tickets escalated and 08 still to build, `next.sh` printed `STEP: build`, but the lead saw ESCALATE in the ticket table and stopped for the human. The prompt now says only the `STEP:` line decides, and `next.sh` adds to a build or review step that the escalated tickets wait for the human afterwards. Separately, salvaging a patch whose change was already integrated ran every check and then stopped on git's "nothing to commit". `integrate.sh` now sees an empty change after applying, says the change is already in this branch, and exits 3 without committing or recording a round.

**D75. A reviewer may dispatch its review axes, and a fix may ask the human.** Since D71 the guard refused every direct `subagent` call, including the one the reviewer brief asks for: dispatching a code-review axis to `factory-review-axis`. In the fix lane the reviewer stopped and asked, and `human.sh ask` refused a fix (no mission spec). The guard now allows exactly `subagent({ agent: "factory-review-axis", task, context: "fresh" })`, a read-only agent; anything else is still refused. A reviewer whose dispatch fails reviews that axis itself and says so. `human.sh ask` and `decide` accept a fix slug (`light/<slug>`); the contract gates still need a mission.

**D76. The fix lane counts added lines.** Removing ten copied lists (229 deleted, 47 added lines) was blocked by the 80-line limit. Deleting code is the safest change there is; the limit now applies to added lines, and the blast radius reports removed lines next to it.

**D77. Every run records its configured model.** `metrics.sh` listed only the judges' models, taken from verdicts. `workflow.sh` now appends one line per run to `runs.tsv` (workflow, key, agent, model, thinking, as configured when the wave was generated, since models change mid-mission), and the metrics list every role with its models and run counts. The build wave also returns each child's `ok`, `error` and, when pi-subagents provides it, its usage.

**D78. The worker's own check is recorded, and can be enforced.** Five tickets escalated on mistakes the self-check catches. Each self-check run now writes its result next to the draft patch; a failed integration says what the worker's last self-check said ("never run", "FAIL tests", "PASS"), and the metrics count red hand-overs. With `FACTORY_SELF_CHECK_GATE=1`, the build wave gives each worker a pi-subagents `gate` that runs the self-check in its worktree when it finishes; a red hand-over is resumed once in the same session with the failure. Off by default until tried on a real gateway: it depends on pi-subagents' gate and resume.

**D79. Each model is probed on its own provider.** On the last day, a second machine used a key that could not call the worker's model (403), and the probe never ran: it knew one gateway (`FACTORY_GATEWAY_URL`) and none was set. The probe now reads each agent's `provider/model` from Pi's `models.json` and calls that provider's `baseUrl` with its key (an environment variable name or the key itself, never printed); `FACTORY_GATEWAY_URL` remains the fallback. A 404 on `/models` suggests a missing `/v1`. The pre-flight requires a fresh probe whenever any agent maps to a provider.

**D80. A conflicting patch never leaves a conflicted tree.** In mission 3, three workers of one wave wrote the same test file; after 03, 04 and 14 were integrated, ticket 05's patch passed `git apply --check --3way` but its 3-way apply conflicted, and `set -e` stopped `integrate.sh` with the file unmerged: every later integration refused the dirty tree, and only a human could clean it. A failed 3-way apply now puts every touched path back as HEAD has it and records a failed round ("conflicts with code integrated since it started; rebuild from the current code"), so the ticket rebuilds on HEAD like any red round.

**D81. A verdict on an older commit is stale, not a round.** In mission 3, ticket 14 escalated on a FAIL that reviewed the README-only commit while its docs had since been integrated in a later commit nobody reviewed. `collect.sh` now keeps such a verdict aside (`state/<ticket>.stale-verdict.md`) when its `Commit` is not the ticket's last integration: no round is counted and the ticket goes back to review.

**D82. A missing deliverable is a FAIL the reviewer decides.** A reviewer asked the human whether to fail a commit that left out the files the ticket named. The reviewer brief now says it is a [blocking] FAIL, never a question, and the resolver answers the question if it is asked anyway (rule `deliverable`).

**D83. Tickets of one wave never write the same file.** Four tickets writing one test file conflicted on integration (D80). The ticket writer gives each its own file or chains them with `Blocked by`.

**D84. Rounds carry a journal, and a round that changes nothing escalates.** Workers end every round with `journal.sh` (what they tried, ruled out, where they stopped); integration moves it into `.scratch/<mission>/journal/<ticket>.md` under its round, and fix rounds read it. A red integration keeps a failure signature (failing tests and lint keys, without times or counts); when the next round fails with the same signature, the ticket escalates at once instead of spending a third round. Borrowed from Machinist's handoff notes and DoorDash's measured progress (P9 steps 2 and 3).

**D85. Tokens per run are recorded.** `usage.sh` reads pi-subagents' per-run metadata (`*_meta.json`: usage, model, duration) and appends each factory run once to `.scratch/<mission>/usage.tsv`; integration and collection run it, and the metrics show the totals. Best effort: no metadata, no line.

**D86. One command opens the merge request.** After mission 3 the human retyped a body from the terminal into GitLab. `mr.sh <mission>` takes `/pr`'s body (`.scratch/<mission>/pr.md`; its `# ` heading becomes the title), pushes the branch and opens the MR against `FACTORY_MR_TARGET`: with glab when it is logged in, else the GitLab API with the token named by `FACTORY_GITLAB_TOKEN_ENV`, else push options and the body to paste. Run again, it updates the open MR. It refuses the target branch itself, branches listed in `FACTORY_MR_BLOCKED_BRANCHES` (some branch names deploy when pushed) and a title that would skip CI. Opening the MR stays the human's act: the script is run by a person, never by the lead.

**D87. The worktree hook's links never cost a round.** In mission 3, 3 of 18 rounds were blocked by the patch guard for a `node_modules` link: the hook links dependencies into each worktree (D65), and a link escapes a `node_modules/` ignore rule. `integrate.sh` now drops, before the guard, new links named like a `FACTORY_DEPS_LINKS` entry and `.env.factory`, and says so; any other link is still blocked.

**D88. A misspelled frozen-paths heading stops the mission.** `## Frozen path` (singular) would have frozen nothing for a mission that is not maintenance. `next.sh` blocks on any heading starting with "Frozen" that is not exactly `## Frozen paths`.

**D89. Hand commits are counted.** P8 counts a manual commit as an intervention, but the metrics only counted decisions: mission 3 showed 4 while four repairs were done by hand. Every commit a factory script makes now carries a `Factory-Script:` trailer; `metrics.sh` counts the others since the spec commit.

**D90. The cockpit reads the files; it never writes them.** The human spent hours reading terminals to learn a mission's state (P10). `status.sh <mission>|--all --json` builds a snapshot from what already exists: next.sh's step, the ticket states (`compute_ticket_state`), verdicts and their round copies, journals, `decisions.tsv`, `runs.tsv`, `usage.tsv`, the mission's commits, and, best effort, pi-subagents' live run logs. `cockpit.sh` serves one static page and that snapshot from a temp folder on 127.0.0.1 (never the repo), rewritten every few seconds; the page zooms leads → mission (Mission Control: active ticket with its preconditions and expected behavior, ticket checklist, gates, live worker, progress log, needs-you with decisions against five) → ticket (rounds, journal). No database, no build, no write path: the factory works the same with the page closed.

**D91. The lead can be a script.** `run.sh <mission>` runs the loop `/factory` describes, step by step from `next.sh`, with no LLM lead: waves are generated by `workflow.sh` and run by a runner (`FACTORY_RUNNER=pi-json`: `pi -p --mode json` with `driver.mjs`, a Pi extension whose "model" is code that makes the one allowed `subagent` call), outcomes go through the same scripts (`integrate.sh`, `collect.sh`, `record-no-patch.sh --provider`, `human.sh ask`). It stops where the lead stops: a human step (exit 0, with the NEXT line), a provider error (mission paused, exit 3), a failed script or unknown step (exit 2). A watchdog stops it when an action leaves `next.sh`'s output unchanged, and a step budget bounds it. It runs pi with `--approve` (trust the project's own `.pi` files): without it the factory guard does not load headless and a child's `git push` runs (P2, spike). Raw runner output (agent text, gateway errors, model ids) stays in the git folder (`<git-common-dir>/pi-factory/runs/<mission>/`), never in the committed mission folder. A provider error is recognised by its shape (`provider_error_line`), not by any 429 or 5xx in a worker's text. `/factory` stays; the spike results are in P2.

**D92. The factory installs once per machine; a project carries only its own files (P11, opt-in).** A spike on Pi 1.3.0 and pi-subagents 0.76.1 showed both halves work: Pi loads a local or npm package's prompts, skills and extensions from its `pi` manifest, and pi-subagents loads its agents from `pi.subagents.agents`; user `subagents.agentOverrides` set the model and thinking of `factory-*` agents (package or copied), and a project's overrides win over the user's. So: the repository is a Pi package (`package.json`, same version as `.factory/VERSION`); `factory onboard` writes the project-owned files and links scripts, briefs, the skills pin and the factory's docs as untracked links (`link.sh`, `.git/info/exclude`; the worktree hook gives worker worktrees the same links); `models-profile.mjs apply --user` sets each machine's models; every script that names a model reads the effective one (`effective-models.mjs`); the pre-flight refuses an installed factory older than `.factory/VERSION`. CI fetches the factory from `FACTORY_PACKAGE_GIT` (a CI variable with no default: the project decides where its CI may fetch code from) at the commit onboard recorded in `.factory/package-sha`, checks the checked-out commit before running anything from it, into a directory of its own, and links it. In CI, models are per machine, so `models-lint --per-machine-ok` skips only the per-agent model checks; settings, agent files and families are still checked. A project's own `factory-*` agentOverrides are kept (they used to be deleted: older pi-subagents crashed on them). Links rather than rewriting every brief and prompt to call a `factory` command: briefs keep naming `scripts/factory/…` and `docs/agents/…`, which agents read as files. `install-into.sh` keeps working as before; `onboard --migrate` moves a copied project over in one MR.

**D93. A refactor is a mission with frozen tests.** After missions 2 and 3 pinned a batch's behavior, the next step is to change its structure and bring it under the team's rules in `AGENTS.md`, without changing what it does. `**Intent:** refactor` needs a `## Frozen tests` section naming the tests that pin today's behavior: `next.sh` refuses to start without it, or when they are not on the branch, and the patch guard refuses any change to them, tests included (unlike frozen paths). The code itself is free. The contract states the structure to reach and each `AGENTS.md` rule to apply as `Kind: code` assertions citing their source, plus one assertion that the frozen tests pass unchanged; a refactor adds no behavior. The code steward now judges every diff against `AGENTS.md` as well as the quality bar.

**D94. The shape of the code is approved before any ticket.** Models are trained to make tests pass, with no penalty for a design that is hard to change, and review agents raise the floor, not the ceiling (HumanLayer, "Why Software Factories Fail"). Feature and refactor missions now get a program design after G1: a `factory-designer` writes `design.md` (call-stack diff, file-tree diff, key types and signatures, the structure before and after for a refactor, the order of slices), each item tied to the assertions it serves, no implementation. A human approves it (`/factory-approve <f> design`, G1b) before the ticket writer runs; the ticket writer follows it and the reviewer's Spec axis checks commits against it. `**Design:** yes|no` in the spec overrides the default. One more human step, deliberately: thirty minutes on the design replaces hours of rework found in review.

**D95. Tickets are vertical slices, and the MR's reviewer approves the plan.** Models plan layer by layer, so nothing runs until the last ticket. The ticket writer now slices vertically: each ticket delivers something observable end to end, thinnest path first. The spec may name the MR's reviewer (`**Reviewer:**`): next.sh asks for them at G1 and G1b, approvals record who approved, and `mr.sh` requests their review (`FACTORY_MR_REVIEWER` overrides). The review then confirms what was agreed instead of discovering it, which is how review stops being the bottleneck without being skipped.
---

**D96. New tests must disagree with the code before the change, the way the intent says.** A model trained on "the tests pass" has no reason to write a test that tests anything; benchmarks that grade quality (Frontier Code) penalize new tests that don't fail on the code before the patch. At integration, before the patch is applied, the patch's test files alone are applied to a temporary checkout of the base and the test command runs once: in a feature or bugfix mission it must fail there (the test proves the ticket; for a bug, it reproduces it), in a maintenance or refactor mission it must pass there (it pins today's behavior). A mismatch is a failed round with the reason and the log; nothing is applied. Self-check runs the same check, so the worker sees it before handing over; `test-on-base.sh <mission> <ticket> <patch> [base]` runs it alone (the benchmark uses it). Not checked: a change with no test files, the fix lane, an intent outside the four, `FACTORY_TEST_ON_BASE=0`, and a ticket that opts out with `## Test on base: skip — <reason>`, which is recorded as a decision. Cost: one extra test run per ticket that adds or changes tests.

**D97. Every run is kept, scored, and counted across missions (P14).** Run transcripts are the factory's most valuable data, and we threw them away. `archive.sh collect` (called by integration and collection) keeps each factory run under `<git-common-dir>/pi-factory/archive/<mission>/<run>/`: brief, answer, transcript, and `run.json` (model, thinking, usage, brief id, ticket, outcome, and the command guard's refusals during the run, which the guard now also logs in the shared git folder). Text is redacted with the patch guard's secret patterns; nothing is committed; `export` and `import` move a mission's archive to where the team keeps history. `score.sh` asks a judge of another model family to check sampled runs against failure modes declared in `.factory/scoring/` (a settled question asked again, a silenced check, edits outside the ticket, no reproduction, redundant tests, context waste); answers must be a strict `SCORE:` and `EVIDENCE:` or they are skipped, and a run is judged once per dimension. Findings are evidence for a person or P5, never an automatic change. `metrics.sh --all` aggregates every mission (decisions and hand commits, rounds, first pass, tokens and cost, scores, cost per merged MR), and the cockpit's leads level shows the totals.

**D98. Models and factory changes are chosen on our own tickets.** Every model choice so far was made once, by feel, on one mission. `bench.sh add <mission> <ticket>` turns a ticket the factory really did into a self-contained case: its issue, its spec (contract, frozen paths and tests), the commit before its first integration, its known outcome, and a difficulty from that outcome (first pass easy, two rounds medium, three hard, escalated extra-hard), an area and the role it exercises (so a suite tests one agent type). `bench.sh run <suite> --config <models profile>` replays each case in a throwaway worktree in the git folder (the worktree hook hides the instrument and links dependencies, as for a worker), with today's briefs, commands and baselines, and scores it with integration's gates: a patch, the patch guard with the case's frozen paths and tests, lint against the baseline, tests, the test-on-base check when this factory has it, and the reviewer with `--review`. Nothing touches the real branch or pushes. The runner is `pi -p --mode json` with the driver (as run.sh), the run's models set as agentOverrides in the throwaway worktree, or any command in `FACTORY_BENCH_RUNNER`. `bench.sh compare` answers first (a written summary and three recommendations: highest quality, most efficient, lowest cost, each with its cost per trial; "most efficient" and "lowest cost" consider only configurations above a quality floor, within 10 points of the default's pass rate or `--min-pass`, so a cheap configuration that fails is shown, marked, and never recommended), then the table by difficulty and area, and writes the points the cockpit's Benchmarks view plots against axes the reader picks. Each configuration should differ from the default by one variable (a role's model or thinking, or the factory's version or briefs); more than one is flagged, and refused with `--strict`, because the result can no longer say which change mattered. `bench.sh probe` runs follow-up cases on the code as it is now: how easy the code left behind is to change, the measure a refactor is judged by. Borrowed from Warp Factories' benchmarks and HumanLayer's "small model tries the next change".

**D99. Context repos: investigate across services, change only one (P13).** A bug between an API and the bots that keep it in sync needs all three repos in view; the fix goes into one. A spec lists the others under `## Context repos`. `context.sh sync` clones them into the factory's own folder (`.factory/context/<name>`, excluded from git, never the human's clones), records the commit read in `context.tsv` and makes them read-only on disk; the command guard refuses writes there, git in them, and any write outside the project (the temp folder excepted), and the patch guard already refuses a patch under `.factory/`. For a bugfix or an exploration naming context repos, `next.sh` runs `context-sync`, then `investigate` waves: one fresh explorer per repo (and one for this repo's side) writes a short brief with `path:line` evidence; the investigator reasons from the briefs, keeps a hypothesis log, asks questions that fresh explorers answer, and concludes where the fix belongs, within `FACTORY_INVESTIGATE_ROUNDS` (default 3). No agent ever holds two repos. A fix here needs a reproduction ticket (`issues/01-reproduce-*.md` with a `**Test:**` line), frozen once integrated (D93); the human approves the conclusion (`/factory-approve <f> conclusion`) and the usual mission starts at the contract. A fix elsewhere ends at `handoff` with a finding for that team; an exploration ends at `report`.

**D100. The hands hold no secrets.** Borrowed from Google's Agent Compute Engine design (October 2026): separate the harness (calls the model) from the hands (run commands), and assume an attacker controls everything the hands run. In Pi both share a process, so a worker's `bash` inherited the gateway key: a spike ran real Pi against a fake gateway whose model asked for `printenv` of three secrets, and got all three. Now the factory guard rewrites every bash call in a factory project to unset credential variables first (the gateway key named by `FACTORY_GATEWAY_KEY_ENV`, variables Pi's `models.json` names as `apiKey`, `*_TOKEN`, `*_KEY`, `*_SECRET`, `*PASSWORD*`; `FACTORY_TOOL_ENV_KEEP` keeps one), using Pi's documented `tool_call` input mutation; the same spike then got three empty values while the harness kept its key. Workers (worktrees on a `pi-subagents/` branch) are kept off the network by rule (downloads, installs, git remotes, interpreter network code) and out of the shared dependency folders linked from the main checkout; Pi's `models.json` and `auth.json` can't be read by any agent. Factory commits are authored by `FACTORY_AUTHOR` (default `pi-factory`) and committed by the human, so the factory's activity is one query. Rules, not a sandbox: without root, a determined injection could still read the harness's environment through another route or find an unnamed network path; the patch guard, the human MR and a machine whose egress is filtered remain the backstops.

**D101. Review of the batch: what the rules really hold.** An independent review of D96–D100 found the rules weaker than their wording. Fixed, each with a test: (1) **/proc and ps**: no agent reads a process environment; any `/proc` path but `cpuinfo`, `meminfo`, `loadavg`, `version` and `stat` is refused, as are `cd /proc`, relative `proc/<pid>/` paths, anything ending in `/environ`, and `ps` with environments (`ps e`, `ps eww`, `ps -E`). (2) **Normalized matching**: every rule sees the command as written, normalized (quotes and backslashes inside words removed, `${IFS}` and newlines turned into separators, so `c''url`, `"curl"` and `\curl` are curl) and with git's global options removed (`-c k=v`, `--no-pager`, `-C path`, `--git-dir`, `--work-tree`), so `git -c x=y push` is a push; git aliases can't be defined inline or in config. (3) **Network rules in command position only** (start, or after `;`, `&&`, `||`, `|`, `$(`, a backtick, and wrappers such as `env`, `timeout`, `sh -c`): `grep -rn http src` and `node x.test.js --url http://localhost:3000` pass; interpreter network code is matched only in inline code (`-c`, `-e`, `--eval`, `-p`). (4) **The keep list** (`FACTORY_TOOL_ENV_KEEP`) comes from the harness's own environment only, never `.factory/commands.env`, and can never bring back the gateway key or a models.json key. The scrub list adds `SSH_AUTH_SOCK`, `GIT_ASKPASS`, `SSH_ASKPASS`, `*JWT*`, `*_AUTH*` (not `GIT_AUTHOR_*`), `*CREDENTIAL*`, `*COOKIE*` and any variable whose value is a URL with credentials. (5) **`.factory/` through bash**: redirections, `tee`, `sed -i`, `cp`, `mv`, `install`, `ln`, `chmod`, `chown`, `rm`, `touch` into `.factory/` are refused like the write and edit tools. (6) **Pi's credential files**: any command or read touching `auth.json` or `models.json` under `~/.pi/agent` or the resolved `$PI_CODING_AGENT_DIR`, and `cd` into them. (7) **One redaction** (`redact.mjs`) for the run archive and the guard log, on raw and JSON-escaped text: private keys, AWS keys, GitHub, GitLab and Slack tokens, `sk-`/`sk-proj-`/`sk-ant-` keys, Bearer tokens, JWTs, URL credentials and `password|passwd|secret|token|api_key` assignments, quoted or not. (8) **Archive ownership**: `archive.sh collect` keeps a run only when its meta file or a path it records is under this checkout (top level, a worktree, the git common dir) or its brief id is one the mission recorded; a foreign run in a shared temp folder is ignored. (9) **Push**: refused for every agent, the lead included, whatever the global options; context clones get the push URL `no-push`, and only read-only git (log, show, blame, diff, grep, ls-files, rev-parse, cat-file, describe, shortlog) runs in them. (10) **Context repos read-only**: agents' chmod, chown, `sed -i`, cp, mv, tee, redirections and rm there are refused, and so is `context.sh release`; `context.sh check` compares source and branch, not just names; a context repo can't be named `home`. The file permissions hold only for non-root users. (11) **Approvals are the human's**: a contract, design or conclusion approval line counts only with the matching row human.sh writes in `decisions.tsv` (same kind and date; for the contract, the latest approve-or-amend row); a line without its row leaves next.sh at the approve step with that reason, and gate.sh, workflow.sh and the cockpit agree. Agents can't write dated approval lines or `decisions.tsv` through write, edit or bash, and a worker can't run a human gate. (12) **Bench agents are workers**: `FACTORY_ROLE=worker`, or a worktree under the git common dir's `pi-factory/bench/`; bench refuses a case worktree without the guard extension and removes case worktrees on any exit or interrupt unless `--debug`. Pi must trust the project for the extension to load. (13) **Test on base**: tests that don't apply on the base, a temporary worktree that can't be made or a test command that can't start are errors (a failed round with the reason), never "not checked"; with `FACTORY_TEST_FILES_CMD` (a template with `{files}`) only the patch's test files run; without it, a feature or bugfix first runs the suite on the base and a red base makes the check inconclusive and the round fail ("base already red: set FACTORY_TEST_FILES_CMD"); the temporary worktree goes on any exit or signal. **What still doesn't hold**: the guard reads command lines, so a command assembled at run time (a variable, base64, a script file the agent wrote, `$'\x63url'`) is not seen; the scrub removes variables by name and value shape, it is a rule-level defence, not proof against an injection that already runs code as the same user; the lead can still run `human.sh approve` itself (a prompt template and a model call look the same to the guard), so the decision log says who, and the human reads it; root ignores the context clones' permissions. The backstops stay the patch guard, the human MR, a user with only the keys it needs and filtered egress.

**D102. Setup by rehearsal: a project's commands are found and proven, not typed.** Onboarding mission 4's project on the installed package took an evening of a person reading red prompts: an old models profile (9 agents of 12), floating model aliases, judges on a production route, `NODE_TLS_REJECT_UNAUTHORIZED=0`, the factory in a subfolder of an internal mirror, an install script running `npm audit fix`, jest configured but not a dependency (`npx` downloaded it), a test file commented out since 2021, an empty `tests/` root, tracked `.env` files with a build step that inlines environment variables, `head` missing from the image, and the skills pin comparing absolute with relative paths (proposal P18). Every one was a fact a script can read or test. Now: (1) **`factory setup`** (per project, run by `factory onboard`; `--no-setup` skips it) discovers the commands from the project's manifests (Node, Python, Go, Rust, JVM, Makefile), its CI file and its install scripts, then **rehearses** them as a worker runs them: in a fresh worktree of the working tree (tracked changes and new files; what isn't committed is named), dependencies linked by the worktree hook (D65), credential variables unset (D100), package managers offline, an empty npm cache and the proxies on a closed port. The test command must be green twice, then red with a planted failing test file, and red because of that file; `FACTORY_TEST_FILES_CMD` must be red on that file alone; lint must run to the end (its errors are the baseline, D62); an extra check must be green; a command `npx` would download fails; files the run leaves in the tree are named. `.factory/setup.md` lists the commands with their source and checks, the decisions for a person (a runner that isn't a dependency, an install script that writes, a CI job a branch push starts, no test command), the findings (tracked `.env` files, build-time inlining) and this machine; `--write` puts the commands that passed into empty `FACTORY_*` lines and never replaces a value someone set. Offline means proxies and package managers, not a network namespace: a program opening its own socket is not stopped. The rehearsal turns off git hooks for its worktree, skips the instrument's sparse checkout (it would turn on `worktreeConfig` in the user's `.git/config`), runs each command in its own process group (a timeout or Ctrl-C stops all of it), judges network errors only on a failed run (a suite may test them) and a lint that exits non-zero without a readable error as a crash, not a baseline. The committed `setup.md` holds no machine-specific text; the machine section is printed, not written. (2) **`env-check.mjs`**, in `doctor` and the pre-flight: the commands the scripts call; agents without a model, by name (an error in `doctor` and setup, a warning in the pre-flight, where a maintenance mission never calls the designer); floating aliases (`latest`, `current`, `default`, `stable`, `preview`); roles on a production route (`FACTORY_GATEWAY_PROD_RE`, else hosts that look like production); TLS checks off; a factory checkout with local changes. (3) **`factory report`**: one redacted text with what a diagnosis needs (pre-flight problems, models and routes, commands, setup's verdicts and open decisions, missions), about 40 lines, `--full` for everything, a copy in the git folder, never committed. (4) Fixes: `head` has a stand-in in `lib.sh` when the machine has none (it reads all its input: an early exit sends SIGPIPE upstream under `pipefail`); the skills pin compares paths relative to `.pi/skills` on the installed package; `onboard` names the agents without a model; a factory that is a folder of its repository is recorded in `.factory/package-dir`, and CI links that folder of the clone (a path leaving the repository is refused).

**D103. The archive collects itself.** The run archive (D97) only held what someone remembered to collect with `archive.sh collect`, while pi-subagents keeps run artifacts in temp folders that a reboot or a cleaner empties. The factory is now run to collect data first, so `run.sh` collects at every stop (each human step, error or pause) and `mr.sh` before opening the MR, where it also writes the mission's metrics next to its runs and exports the whole archive to this machine's data folder (`FACTORY_DATA_DIR`, default `~/.pi-factory/data/<repo>/<mission>-<date>.tar.gz`), outside every repository; best effort, never a reason to stop. Scoring stays a command: it spends judge calls. `archive.sh collect` takes only runs not archived yet, so collecting often costs nothing.

**D104. Depth before the spec.** A task described in a few lines tends to become a spec of the same size: the ticket as asked, checked by the model that wrote it. The `deep-prompt` skill (from Felix Rieseberg's "How to be more ambitious", the Depth practice) runs before the grilling and answers four questions: what a top practitioner would do that wasn't asked, the rawest material they would start from, the methods and tools they would use, and what other than the model or the human shows the result is right. It writes `.scratch/<mission>/depth.md`; its outside checks are candidate contract assertions, and the human starts the grilling on it (the grilling skill is pinned upstream, so it is named as input, not wired in). Optional, human-invoked, and it never starts the work; small tasks get one line saying so.

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
