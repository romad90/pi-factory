# ADR-001 — Agentic factory on Pi

**Revision:** next. pi-subagents orchestration, generated briefs, deterministic integration, mattpocock/skills v1.3.1 enforced.
**Status:** Proposed
**Date:** 2026-10-07
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
- **pi-subagents (nicobailon) 0.76.1**: per-role model overrides with fallbacks, model scope enforcement, workflow scripts with per-child worktrees and a setup hook, a supervisor channel, Herdr integration.
- **Boris Cherny's Steps of AI Adoption** (July 2026), §10.

---

## 2. Decisions and the reasons behind them

Each decision states its reason. If the reason stops being true, revisit the decision. Superseded decisions are kept, marked, so the history reads straight.

### Structure

**D1. Use upstream skills for every role they cover; pin one version; never fork them.**
*Why:* maintained elsewhere, upgrades are file replacements, our effort goes to the gaps. Enforced by D36.

**D2. Each role runs in a fresh subagent and communicates only through files.**
*Why:* a context that saw the work is biased judging it, and long contexts dilute attention. Files are also the audit trail. Mechanism: D30, D32.

**D3. Missions live in `.scratch/<feature>/` and are committed.** `checkpoint.sh` commits mission state before each build wave.
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
*Why:* running every subagent on its own model is a hard requirement. pi-subagents layers per-run, frontmatter, per-role settings and default models; gives each role cross-provider fallback models on quota or outage; enforces a model scope; and shows the live mapping (`/subagents-models`). It also brings worktree setup hooks (D35), a supervisor channel (D37) and Herdr integration. One package only: two orchestration tools confuse the lead. Pinned because it moves fast.

**D30. Factory roles are repo-defined agents** (`.pi/agents/factory/`). Builtins are disabled. Every factory agent: `defaultContext: fresh`, project instructions inherited (AGENTS.md rules reach every role), `inheritSkills: false` with explicit `skills` and `skillPath` to the pinned copy, no agent memory, strict tool lists.
*Why:* the package's builtin `worker`/`oracle`/`advisor` default to forked context (the lead's conversation) and its builtin `reviewer` makes fixes, both against D2 and D12. Memory could carry instrument details past the wall.

**D31. Each factory agent declares its own model in its frontmatter** (`model`, `fallbackModels`, `thinking`). `.pi/settings.json` keeps only package-level guards: builtins off, `modelScope.enforce`, root resolution. Family separation (D13) is checked across primary *and* fallback models by `models-lint.mjs`, in CI.
*Why:* every subagent must run on its own model, and the frontmatter is the documented, authoritative place for it. Revised after S0: pi-subagents 0.76.1 only accepts **builtin** names in settings `agentOverrides`; project agents there crash agent discovery ("Builtin override 'factory-…'"). `migrate-models.mjs` moves existing overrides into frontmatter; the lint fails on any `factory-*` left in `agentOverrides`. A fallback that lands a reviewer on the worker's family would silently undo D13, so fallbacks count. Models are template-owned: set them once in the template repo, `install-into.sh` propagates them.

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

---

## 3. Flow

```
HUMAN, main session       /grill-with-docs → /to-spec → .scratch/<f>/spec.md
                                                                       D3, D4
/factory <f>   (lead loop: next.sh → act → repeat)
  contract     workflow.sh contract → author, then critic             D5, D32
               (fresh; critic on another family)                      D13, D31
  ── G1, HUMAN: approve the contract (or rerun to amend) ─────────────  D7
HUMAN          /to-tickets (## Covers on each) → checkpoint.sh
  ── G2: coverage.sh clean ─────────────────────────────────────────── D6
  build        checkpoint.sh → workflow.sh build-wave                 D33
               ≤4 factory-workers in parallel, own worktrees,         D16, D27
               instrument hidden, own port; heavy model after round 2 D21, D24, D35
               → integrate.sh per patch: lint + tests → commit        D8, D34
  review       workflow.sh review-wave → fresh reviewers, other      D2, D13
               family; code-review axes dispatched to review-axis
               → verdicts/<ticket>-code.md with brief id             D12, D32
  ── G3: every ticket PASS on its latest integration ──────────────── D34
  validate     workflow.sh validate → validator in main checkout,     D14, D15
               holds the instrument → verdicts/behavior.md           D22, D23, D25
  ── G4: behavior PASS on current code ─────────────────────────────── D10
  pr           checkpoint + metrics.sh → HUMAN: /pr, MR, /retro      D20, D26
CI             factory-config (skills pin, models), factory-gate      D9, D31, D36
               (G1–G4, lanes, briefs, instrument rule), readiness     D11, D23, D28
```

**Light lane** (no behavior path touched, chosen by CI): `/factory-light <slug> <base>`, one fresh reviewer → `.scratch/light/<slug>/verdicts/code.md`.

---

## 4. Artifacts

| Artifact | Path |
|---|---|
| Spec + contract, critique | `.scratch/<f>/spec.md`, `contract-critique.md` |
| Tickets | `.scratch/<f>/issues/NN-<slug>.md` |
| Integration markers, logs | `.scratch/<f>/state/<ticket>.integrated`, `logs/` |
| Verdicts | `.scratch/<f>/verdicts/<ticket>-code.md`, `behavior.md`; light: `.scratch/light/<slug>/verdicts/code.md` |
| Instrument (validator only) | `instrument/scenarios/`; raw results `instrument/results/` (ignored) |
| Factory agents | `.pi/agents/factory/*.md` |
| Models per role | `.pi/agents/factory/*.md` frontmatter |
| Scope, builtins off | `.pi/settings.json` (`subagents`) |
| Model families + rules | `.factory/model-families.json` |
| Brief templates | `.factory/briefs/<role>.md` |
| Pinned skills | `.pi/skills/`; pin in `.factory/skills-pin/` |
| Lead playbooks | `.pi/prompts/factory.md`, `factory-light.md` |
| Integration commands | `.factory/commands.env` |
| Lane rule | `.factory/behavior-paths` |

---

## 5. Gates

| Gate | Condition | Where |
|---|---|---|
| G1 | Critique exists; human added the dated approval line | `gate.sh`, `next.sh` |
| G2 | Every assertion covered; tickets justified; no unknown IDs | `coverage.sh` |
| G3 | Each ticket PASS, on its latest integration commit, with a generated brief id | `gate.sh` |
| G4 | Behavior PASS on current code, with a generated brief id | `gate.sh` |
| Lane | Behavior paths → mission required; else fresh light verdict | `gate.sh mr` |
| Instrument | Changed/removed cases need a contract amendment | `gate.sh mr` |
| Config | Skills match v1.3.1 pin, no shadows; models per role, families separated | `factory-config` |

**"Pipelines must succeed" must be enabled**, or every gate is advisory.

---

## 6. Roles

| Role | Agent | Skills | Tools | Model (settings) |
|---|---|---|---|---|
| Clarifier, spec, tickets | human + main session | grill-with-docs, to-spec, to-tickets | — | session model |
| Contract author | factory-contract-author | contract | read, write, edit | frontier, family A |
| Contract critic | factory-contract-critic | contract-critic | read, write (critique only) | frontier, family ≠ A |
| Worker | factory-worker | tdd, codebase-design | all builtins | efficient, family C |
| Escalated worker | factory-worker-heavy | tdd, codebase-design | all builtins | frontier |
| Reviewer | factory-reviewer | code-review | read, bash, write (verdict), subagent | frontier, family ∉ workers |
| Review axis | factory-review-axis | — | read, bash | frontier, family ∉ workers |
| Validator | factory-validator | verify-behavior | read, bash, write | frontier, family ∉ workers |
| Lead | main session, `/factory` | bundled pi-subagents skill | subagent | session model |

---

## 7. Skill inventory

`.factory/skills-pin/UPSTREAM.md` has the full list, roles and upgrade procedure.

- **Upstream v1.3.1 (18):** grilling, grill-with-docs, grill-me, domain-modeling, codebase-design, to-spec, to-tickets, setup-matt-pocock-skills, tdd, code-review, diagnosing-bugs, pr, retro, improve-codebase-architecture, writing-for-agents, handoff, teach, setup-pre-commit.
- **Local:** contract, contract-critic, verify-behavior.
- **Not vendored:** implement, implement-spec (orchestration is D33), and the rest.

---

## 8. Consequences

### Positive

- **Unbiased dispatch is structural:** fresh context by agent default, generated briefs, ids checked at the gate (D30, D32).
- **Every subagent on its own model,** with fallbacks that can't break the family rule (D31).
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
| The wall is soft | Accepted for Step 2 | AGENTS.md rule; separate repo if a worker is caught reading it |
| Package moves fast | Pinned | Upgrade like skills: read changelog, rerun S0 |
| Bot harness missing | One-time cost | First mission (D14) |

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| "Pipelines must succeed" off | S0 checklist |
| pi-subagents result shape differs from what `workflow.sh` returns (e.g. where the patch path is) | Lead finds the patch in artifactPaths or the handoff manifest; adjust the `return` lines in `workflow.sh` once, at S0 |
| Skills under `.agents/` registered as agents | They live in `.pi/skills/`; `skills-pin.sh verify` fails on markdown under `.agents/` |
| code-review axes fail because builtins are disabled | Reviewer dispatches axes to `factory-review-axis` (repo agent, fresh) |
| Model ids not available on LLM-as-a-service | `models-lint` + `/subagents-models` at S0; fallbacks per role |
| Node missing on a runner | CI installs it; locally Pi brings it |
| Mission state not committed before a wave | `workflow.sh build-wave` refuses until `checkpoint.sh` |
| Laptop sleeps mid-mission | `caffeinate`/`systemd-inhibit`; background runs survive only while the machine is up |

---

## 10. Where we are on Boris Cherny's ladder

Steps: **1 Assisted** (one agent, you hold the context), **2 Parallel** (~10 agents, AI writes and humans verify), **3 Supervised autonomy** (agents delegate to agents, humans supervise outcomes and exceptions), **4 AI-native** (AI decides what to work on).

**Today: Step 2 mechanics, without the trust layer.** Isolated subagents and parallel workers were already in use. This revision adds the trust layer and the orchestration: what remains is running it and collecting evidence.

| Step 2 ingredient | Status |
|---|---|
| Agents in isolated worktrees, in parallel | In use; now with the instrument hidden and ports (D35) |
| Self-verification loop you trust | Built: contract, critic, integration gate, fresh reviewers, validator, CI (D4–D13, D32–D34) |
| Automated review on another model | Built and enforced (D13, D31) |
| No permission prompts stalling agents | Check pi-subagents `permissions` / `authorityPolicy` at S0 |
| You review final diffs, not every step | Verdicts + metrics in every MR (D26) |

**Step 2 is declared when**, over 4 missions: 3–4 tickets per wave as routine; MRs approved from verdicts and metrics with spot checks only; first-pass review rate and escaped bugs stable or improving; zero unexplained bypasses.

**Toward Step 3 (later, from the laptop):** the pieces are now in the same package: nested delegation, durable missions and schedules, the supervisor channel, Herdr integration. Triggered work (ticket → mission) waits until Step 2 is declared.

---

## 11. Path to Step 2

| Move | What | Exit |
|---|---|---|
| **S0: Set up and dry-run** | Install pi-subagents 0.76.1, remove tintinweb; `install-pi-config.sh`; fill `.pi/settings.json` models and `commands.env`; `/setup-matt-pocock-skills` (local markdown tracker); paste `AGENTS.factory.md`; `doctor.sh` green; in Pi: `/subagents-doctor`, `/subagents-models`, list agents (only `factory-*`). Dry-run `/factory` on a toy mission with one ticket. | One toy ticket goes build → integrate → review → PASS. Any mismatch in workflow fields or patch location fixed in `workflow.sh`/playbook |
| **S1: First real mission** | `/factory` on a small bots feature; behavior in interim mode (no harness) | One MR merged with metrics |
| **S2: Behavior** | Harness as a mission; instrument; `behavior-replay` in CI | G4 passed with the wall in place |
| **S3: Evidence** | 4 missions, parallel waves | §10 criteria met → Step 2 declared |

**Checks for the S0 dry run** (documented behavior I couldn't execute here): `runs.run`/`runs.all` accept `{ key, agent, task, worktree }`; results expose `output` and `artifactPaths`; where the worker's patch file sits in the handoff manifest; the setup hook runs for `worktree: true` children; a reviewer can spawn `factory-review-axis` children (depth 2).

**Deliberately deferred:** triggered automations, scheduled runs, separate instrument repo, GitLab issues as tracker, team rollout on OpenCode.

---

## 12. Metrics

`metrics.sh <feature>` per mission: intent, assertions, amendments, tickets and fix tickets, first-pass review rate, review and behavior rounds, cycle time, tokens, models. Across missions: those plus escaped bugs and bypasses. They are the evidence for Step 2 and the data for quota discussions.

---

## 13. Open questions

1. Which models and families does LLM-as-a-service offer, with which provider prefix for `modelScope.allow`?
2. Does pi-subagents' `permissions` config need an allowlist so parallel workers never stall on prompts?
3. Harness: local instance or preview environment? Which tools are mocked?
4. Team rollout: OpenCode reads skills from its own locations. Mirror `.pi/skills/` for them, or move the team to Pi?
