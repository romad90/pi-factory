# P17. Plans that leave no decision: readiness, reuse, plain words, drift

**Status:** draft, after mission 4 · **Effort:** S to M, one part at a time · **Depends on:** D94 (design step); P14's benchmark to prove each part

## Problem

Most of the questions that reach the human during a mission are design choices the plan left open: the error to return, the field name, where a helper lives. The worker can't decide them, so it asks, or worse, decides alone and the reviewer finds it later. Each one is a human decision or a round, the two numbers the pilot tracks.

Three more gaps, smaller:

- Nothing checks that the design reuses what the code already has. "Reinventing the wheel" is a classic pattern of model-written code, and a review that never searches the code can't see it.
- A contract or design can use a term nobody defined. The next agent, starting fresh, guesses its meaning.
- After the decisions of a mission, the spec, the contract and the code can say different things. The drift check is on the roadmap (C10) and not built.

Google's Elephant-Goldfish Model (EGM, October 2026, Apache 2.0) attacks the same problems with zero-context reviewers. Its core idea, a fresh context per reviewer, is already ours. Four of its checks are not.

## Proposal

Four additions to roles we already have. None is a new agent unless noted. Each goes in alone, and is kept only if the benchmark and the next missions' decisions count show it helps.

### 1. The zero-decision rule for the design and the tickets

A plan passes only if a competent engineer new to the code could implement it **without making a design choice**: no schema, API path, dependency, error-handling strategy or edge-case behavior left to the implementer.

- The contract critic's checklist gets a readiness pass on `design.md` before G1b, and the ticket writer's self-check gets it on each ticket.
- Each open choice found is written as a question in `design.md`'s `## Open choices`, answered by the human at G1b, all at once, instead of one at a time during the rounds.
- Measured by: questions per mission asked during build rounds (should drop), human decisions per mission (should not rise: the questions move, they don't multiply).

### 2. Reuse before new code

When the design adds a module, helper, type or dependency, the designer must search the code for an existing one and write what it found: `reuses <path>` or `new: searched <terms>, nothing found`. The critic re-runs the search on a sample. The code steward (G5) flags new code that duplicates existing code, with the cloned-code share already in the health ratchet as the number behind it.

### 3. Plain words: the naive reader

The contract critic gets a "fresh reader" pass: every term, service or acronym in the contract and the design is either defined there, in `GLOSSARY.md`, or linked. Undefined terms go to the glossary before G1. Most useful in maintenance missions, where the code's own vocabulary is the thing being documented.

### 4. The drift check before `/pr` (roadmap C10)

At `STEP: pr`, a fresh checker compares spec, contract, tests, README and `decisions.tsv`. Ours can be more exact than EGM's prompt-only report, because the contract has assertion IDs:

- by code: each assertion ID has a test that names it, and each test that names an ID points to an assertion that still exists;
- by a judge, from another family: for each decision in `decisions.tsv`, does the spec still say the opposite?

Drift found is a fix ticket or a spec edit before the MR, never a silent pass.

### Also: prove the fresh context

EGM tests that a reviewer sees nothing from the parent session. Our principle, "a brief of file paths, never the lead's summary", is checked in `workflow.sh`, not on the running agent. A probe in `self-check.sh` runs one reviewer on a fixture and checks its context holds only its brief and the files it read.

## Trade-offs

| For | Against |
|---|---|
| Questions answered at G1b in one sitting, not mid-build | A longer design step; for a small mission the fix lane is still the answer |
| Reuse checked by search, not by the reviewer's memory | Search finds names, not intent: a duplicate under another name passes |
| Drift caught before the MR, partly by code | One more step at the end of every mission |
| Each part measured before it is kept | Needs P14's benchmark and a few missions to tell |

## Not taken from EGM

The plugin itself (written for interactive sessions in Claude Code, Codex or Antigravity, with one-question modal gates that clash with `run.sh`); its long, all-capitals prompts tuned for frontier models; verdicts that are only a model's opinion.

## Plan

1. Zero-decision readiness pass in the critic and ticket writer; `## Open choices` in the design format; count questions per phase in `metrics.sh`. **S**
2. Reuse search in the designer's brief and the critic's checklist; duplication flag in G5. **S**
3. Naive-reader pass and glossary step before G1. **S**
4. Drift check at `STEP: pr`: ID coverage by code, decision drift by a judge. **M**
5. Fresh-context probe in `self-check.sh`. **S**

## What it borrows

- EGM (Google, Apache 2.0): the Implementation Readiness standard's zero-decision rule; the Zoom Out reviewer's mandatory code search; the Comprehension (naive reader) reviewer; the drift report; tests that a reviewer's context is clean.
- HumanLayer: front-load alignment, the design argued before code exists (D94).
