# P14. Measure and improve: a run archive, a benchmark from our own tickets, scoring

**Status:** run archive, scoring and metrics across missions shipped (D97); benchmark shipped (D98: cases, runs, comparisons, probe, cockpit view) · **Effort:** M (archive S, benchmark M, scoring S) · **Depends on:** nothing to start; P5 builds on it, P11's manifest makes it one command

## Problem

The factory improves through retros: a person reads what happened, finds a pattern, and writes a rule. It works (mission 2 cost 31 human decisions, mission 3 cost 4), but three things are missing to make it a measurement rather than an opinion:

| Question we can't answer today | Why |
|---|---|
| Is Qwen the right worker? Is Gemma at thinking high worth it as reviewer? | Every model choice was made once, by feel, on one mission |
| Did the last brief change help, or did the mission just happen to be easier? | Nothing replays the same work with the old and the new factory |
| Which failure modes cost us most, across missions? | Run transcripts are thrown away; verdicts and `usage.tsv` keep outcomes, not behavior |
| What does a merged MR cost, and is it going down? | `metrics.sh` is per mission; nothing aggregates across missions |

Three independent sources arrived at the same answer in October 2026 ([ideas](ideas.md)): Factory's Missions learn from repeated work, Google's Harness² keeps only harness edits that measurably change behavior, and Warp's factories keep every agent run, score them, replay real tasks as a benchmark across models and harnesses, and let agents propose fixes to the factory definition.

## Proposal

### 1. A run archive

Every factory run keeps what it did, outside the project's MRs: the transcript (pi-subagents' output log), the brief, the model and thinking level, `usage` (tokens, cost, turns, time), and its outcome (verdict, gate results, integrated commit or not).

- Where: `<git-common-dir>/pi-factory/archive/<mission>/<run>/`, next to the draft patches and run logs (D73, D91): never committed, never in an MR, outliving worktrees.
- `archive.sh export <mission>` packs a mission's archive into one file for the machine that keeps the history (a factory data folder, a bucket); `archive.sh import` reads it back. The data stays on our systems (sovereignty).
- Secrets: the archive goes through the same secret scan as patches; a transcript with a match is kept with the match redacted.

### 2. A benchmark from our own tickets

A benchmark case is a ticket that was really done: its issue file, the contract assertions it covers, its base commit, and the outcome we know (passed, after N rounds, with which verdict).

- `bench.sh add <mission> <ticket>` records a case in `.factory/bench/cases.tsv` (committed in the factory's own data, not the project): mission, ticket, base commit, why it is interesting (hard, typical, a known failure).
- `bench.sh run <suite> --config <profile>` replays each case: a fresh worktree at the base commit, the same brief, the worker (and reviewer) from the given models profile, then the deterministic gates the factory already runs: patch guard, lint against the baseline, tests, and, for the cases that have them, the frozen or characterization tests. A case passes when integration would have accepted it; review runs on the passes only (cost).
- Output: `bench/<suite>/<config>.tsv` (case, pass, rounds, tokens, cost, time) and a summary per config: pass rate, cost per passed case, median turns. Two or more configs give the cost-versus-correctness curve.
- Side effects: replays run in worktrees, with no push, no MR and the command guard on; cases that needed a network service run with the same test doubles as the mission did, or are marked not replayable.

The results page (seen in Warp Factories' benchmark view):
- **One variable at a time.** Each configuration differs from a named default by one thing (the model, or the thinking level, or a brief); `bench.sh compare` warns when two configs differ by more, since the result then can't say which change mattered.
- **A written summary first,** then three recommendations: highest quality, most efficient (quality per unit of cost), lowest cost, each with its score and cost per trial.
- **A scatter with selectable axes:** correctness, cost per trial, turns, time, rounds; one point per configuration, labelled `model (thinking)`.
- **Difficulty and area** on every case (easy to extra-hard from the case's known rounds; an area tag; the role it exercises), so a suite tests one agent type and results break down by tier.
- **Debug a single case** before running a whole suite.

What it answers: which worker, reviewer and thinking level for each kind of ticket, at what cost; whether a change to a brief, a resolver rule or the factory version helps, on the same cases. It turns the budget question for the committee into a number: cost per accepted ticket for the chosen setup.

### 3. Scoring past runs

Our gates already score what is deterministic: rounds, guard blocks, stale verdicts, no-progress rounds (D84), hand commits (D89). Scoring adds what only reading the transcript shows, by an LLM judge on a sample of archived runs.

- Dimensions are declared in `.factory/scoring/<name>.md`: what to look for, pass and fail examples, which roles it applies to, the sample rate. First set: asked a question already settled in `decisions.tsv`; tried to silence a check; changed files outside the ticket; fixed without reproducing first (P9); wrote tests that repeat existing ones; read far more than the ticket needed (context waste).
- `score.sh <mission>` samples runs, asks a judge from another family than the run's model, and appends to `.scratch/<mission>/scores.tsv` (run, dimension, pass or fail, evidence quote).
- The judge's findings are evidence for a person or for P5, never an automatic change.

### 4. Then P5 closes the loop, with proof

P5's strategist reads the scores, the retros and the journals, groups repeated failures ("asked a settled question, 12 runs, 3 missions, mostly the reviewer"), and proposes a change to the factory: a brief line, a resolver rule, a model for a role. **The proposal comes with a benchmark run**: the same suite on the current factory and on the proposed one. The human merges it, or not, on that evidence. This is Harness²'s rule (keep only edits backed by observed behavior) with real verifiers instead of behavioral contrast, and Warp's self-improvement loop without letting a model edit the guardrails: the patch guard and the command guard stay code that no proposal touches.

### 5. Flow metrics across missions

`metrics.sh --all` aggregates every mission in the repo, and the cockpit's leads level shows it: human decisions and hand commits per MR, time from spec to MR, cost per merged MR, rounds per ticket, revert rate (from the target branch's history), sliced by role and model. This is the chart the three-month pilot ends with.

## Trade-offs

| For | Against |
|---|---|
| Model and brief choices made on our own tickets, not public benchmarks or feel | Replays cost tokens: a suite of 10 cases × 3 configs is 30 worker runs; run it on a schedule or before a change, not continuously |
| The committee's budget question answered with cost per accepted ticket | Characterization tickets are the easiest to replay; feature tickets with services need their test doubles |
| Improvements proven before they are merged | LLM-as-judge is noisy: sampled, cross-family, quoted evidence, and never acted on alone |
| Transcripts, the factory's most valuable data, are kept on our systems | Storage and a retention rule; transcripts can hold code and data from the repo, so the archive is as sensitive as the repo itself |

## What it borrows

- Warp (founder's talk, October 2026): factories as code, the run archive as the key asset, scoring with LLM-as-judge on samples, a benchmark suite from your own tasks replayed across models and harnesses, a cost-versus-correctness curve, model routing from it, agents proposing PRs to the factory definition, cost per PR as the headline metric.
- Google Harness²: keep a harness edit only when it changes behavior for the better on the same task.
- Factory Missions: learning from repeated work.

### Judging the refactor mission with the probe

Before the refactor starts, write two or three follow-up tickets that a later change would plausibly need (a new mode, a changed rule), and add them with `bench.sh add-file <issue.md> <mission>` (kind `followup`). Run `bench.sh probe default --config <cheap profile> --at <commit before the refactor>`, then the same at the refactor's last commit. The frozen tests prove behavior did not change; the probe's pass rate (and its cost and turns) shows whether the code got easier to change. Same cases, same cheap model, two commits: one variable.

## Plan

1. Run archive: keep transcripts, briefs, usage and outcome per run; `archive.sh export|import`; secret redaction. **S**
2. Benchmark: `bench.sh add|run`, replay in worktrees with the existing gates, results per config. First suite: 10 tickets from missions 2 and 3. **M**
3. First comparison: the current worker against one cheaper and one stronger model, and thinking medium against high for the reviewer. Feeds the committee deck. **S**
4. Scoring: dimension files, `score.sh`, `scores.tsv`, shown in the cockpit. **S**
5. `metrics.sh --all` and the leads-level chart. **S**
6. P5 proposals carry a benchmark run. **with P5**

## Open questions

- Where does the archive live for the team: one factory data repo per domain, or a bucket? Proposed: a private data repo, one folder per project, exported after each mission.
- Which tickets make a good suite? Proposed: a mix of first-pass passes, tickets that took three rounds, and one escalation, so the suite tells good setups from bad ones.
- Should a replay also run the reviewer? Proposed: yes on passes only; a setup whose patches pass tests but fail review is not cheaper.
