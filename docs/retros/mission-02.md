# Retro: mission 2

Factory findings from the second mission: characterization tests for a batch worker with six modes, in one folder of a monorepo (anonymized). Intent: maintenance. Gateway: shared team key, 10 requests and 45k tokens per minute per model, six models allowed. One file per mission; findings are added **while** the mission runs.

Priority: **P1** blocks or wastes a lot · **P2** friction · **P3** nice to have. **Status** points to the release, PR or roadmap item.

## Gateway and models

Most of the human time lost in this mission came from here. None of it was visible to the checks that existed: every pre-flight passed.

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 1 | A provider error (429) counted as a failed round | Three tickets escalated in two minutes, no line of code written | `record-no-patch.sh --provider`: no round, mission paused | P1 | ✅ PR #25 (D58) |
| 2 | Models the gateway refuses (403) passed every check | Worker on a model not allowed for the key | `models-probe.mjs`: compares agents to `GET /models` | P1 | ✅ PR #25 (D59) |
| 3 | A thinking level the provider refuses (400) | `reasoning_effort medium is not supported, only high or none` | Probe sends each agent's thinking level | P1 | ✅ PR #25 (D59) |
| 4 | A provider rejects a user turn after a tool result (400) | Worker died after a few tool calls: `Unexpected role 'user' after role 'tool'` | Probe replays that order; such models only for single-pass roles | P1 | ✅ PR #25 (D59) |
| 5 | Reasoning sent back in the history refused (422) | `reasoning_content` extra input on the second turn | Thinking off for that model; probe | P2 | ✅ PR #25 (D59, partial) |
| 6 | Quota too small for a worker, not visible before the wave | 10 req / 45k tokens per minute; the lead and a worker shared one model's quota | Probe reads quota headers and warns; one model per role | P1 | ✅ partial PR #25; quota raise is the real fix |
| 7 | Wave size only settable through the environment | `FACTORY_MAX_PARALLEL` in `commands.env` ignored | Read from `commands.env` | P2 | ✅ PR #25 |
| 8 | No compatibility table per model and role | Same lesson learned three times (thinking, message order, loops) | Probe results recorded per model; models profile notes | P2 | roadmap |
| 9 | A model allowed by the scope glob blocked at launch | `models-lint` PASS with `provider/*`, subagent launch refused | Probe checks what will really run; investigate scope matching | P2 | open |

## Lead and agents

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 10 | A lead model that doesn't hand the turn back | Interview: asked via `echo`, kept going, wrote a test file, ~4M tokens | Lead model chosen for instruction following; rule: a question ends the turn | P1 | ✅ cheat sheet; AGENTS.md note planned |
| 11 | Lead wrote outside its role | Edited `src/`, wrote tests during the interview; added `.scratch/` to `.gitignore` and committed | Guard: lead can't write `src/`, `test/`, `.gitignore`, can't `git commit` | P1 | roadmap S |
| 12 | Lead announces an action and stops (thinking off) | "We need to run doctor." then end of turn | Steadier lead model; nudge | P3 | known |
| 13 | Contract author deleted spec text | Implementation notes, deliverables and out-of-scope removed | Check after the contract step: spec diff is additions only | P1 | roadmap C |
| 14 | Contract author imported the target rules into a maintenance mission | `BotExecutionResult`, exit codes 2–4 asserted on code that doesn't produce them | Intent passed to author and critic: current behavior is the reference | P1 | roadmap C |
| 15 | The critic pushes the pack's target rules on characterization | Batch checklist flagged exit codes, dry-run | Same as 14 | P2 | roadmap C |
| 16 | Ticket writer put every assertion on the enabler ticket | Harness ticket "covered" all 30 assertions | Enablers cover only what they make true | P2 | roadmap F |
| 17 | Literal values pinned at contract time are costly | Second contract round: 28 min, 2.6M tokens | Contract fixes the assertion shape; workers record values by running the code | P2 | cheat sheet |
| 18 | Ponytail persona turns itself back on in every new session | Footer `ponytail: FULL` after each `/new` | Install it off in factory projects (also seen: `caveman` persona) | P3 | roadmap |
| 28 | Ticket writer made a check-only ticket with no `## Blocked by` | Ticket 10 "verify `src/` unchanged, unmocked calls fail" was buildable before any test existed, and asked for no patch | G3 refuses a ticket that changes no file; final checks (no change in `src/`) belong to validate, not to a ticket | P2 | roadmap F |
| 29 | The lead's own model quota was never checked | `mistral-small-2603`: 5 requests per minute per key; the lead's short commands hit it in seconds, Pi retried 4 times | The probe reads the lead's model too; pick a lead model with headroom (P1) | P2 | roadmap |
| 30 | A working harness recorded as "no patch" three times | The wave returned `null`; the lead skipped `locate-patch.sh`; the patch lived only in the worktree | `integrate.sh` locates the patch itself; worktree fallback (D60) | P1 | ✅ D60 |

## State and git

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 19 | Generated workflow file left untracked | Every wave: `worktree isolation requires a clean git working tree` | Checkpoint after writing the file | P1 | ✅ PR #24 |
| 20 | `.scratch/` git-ignored made checkpoints fail | `git add` refused, exit 1 | Pre-flight fails when `.scratch/` is ignored | P1 | ✅ PR #25 |
| 21 | Auto-checkpoint committed unapproved contract work | A restore landed on the author's version, not the human's | Keep a ref to the human spec; restore from it | P2 | roadmap |
| 22 | `next.sh` showed `approve` after a failed author run | Critique older than the spec, no contract | `next.sh` checks the contract exists and the critique is newer | P1 | roadmap C |
| 23 | Amendments file rewritten after being recorded | `M` on `amendments/` | Treat `amendments/` as append-only | P3 | roadmap |
| 24 | Invisible character in the mission name | `STEP: grill` on an existing mission (non-breaking space) | Strip whitespace from the mission argument | P3 | roadmap |

## Install and monorepo

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 25 | Prompt frontmatter broke YAML | `Nested mappings are not allowed` | Quoted descriptions | P2 | ✅ 1.3.1 |
| 26 | Retry block missing from installs | 429 failed waves | Installer merges `retry` | P1 | ✅ 1.3.1 |
| 27 | "Repo root" ambiguous in a monorepo folder | Agents wrote at the git root | Monorepo note in AGENTS.md | P2 | ✅ 1.4.0 |

## Measures

| Measure | Value |
|---|---|
| Manual estimate | 70 developer days (7 people × 2 weeks) |
| Human time, spec and decisions | ~4 h (interview 1h30, spec review, contract review) |
| Human time, setup and infrastructure | ~6 h over two evenings, almost all on findings 1–7, 19–20 |
| Contract | G1 approved after 3 rounds (1 lost to a model that invented behavior) |
| Tickets | 10, G2 passed |
| Build | not started at the time of writing: first worker reached the code, stopped on finding 4 |
