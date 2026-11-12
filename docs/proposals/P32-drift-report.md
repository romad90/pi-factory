# P32. Drift report: the spec says what was decided, and the docs say what the code does

**Status:** draft, for review; nothing is built until missions show the need · **Effort:** M (mission drift), then a mission (project drift) · **Depends on:** `decisions.tsv`, the `/pr` step; builds roadmap item C10 and P17 section 4

## Problem

Two kinds of drift, and the factory checks neither.

**Mission drift.** A mission's decisions change what the contract means, and nothing writes them back. eslint-10 is merged, and its contract on master still says:

- VAL-CONF-001: `no-unused-vars` has "exactly six keys". The decision of 2026-11-10 made it nine.
- VAL-TEST-001: "694 assertions in total: 693 passed". The same decision made it 695 and 694.

The next reader of that spec, a person or an agent, gets the wrong numbers. The roadmap has had this since mission 1 (C10, "spec still described the old design after decisions"), and P17 section 4 planned it. It was never built.

**Project drift.** The project's own documentation against its code. The gym has 13 files under `docs/` (client, server, filters, DN, errors, examples, a guide) and nobody has compared them with `lib/` since the fork.

## Source

The drift report of Google's Elephant-Goldfish Model plugin (`skills/egm-drift-report`, Apache-2.0, read at its source). For each design document it finds the code the document describes and reports only the differences: missing features, incomplete models, hard-coded values where logic was planned, a different architecture. One agent, one document at a time, one dated report.

It covers project drift. Mission drift is ours: the plugin has no decision log to compare with.

## Design

### Mission drift, before `/pr` (mostly a script)

1. For every `decisions.tsv` row of kind `decide`, `amend` or `rereview` that names an assertion id, the script checks that the assertion carries an `**Amended:**` line dated on or after it, or that the spec lists it under "Superseded by decisions".
2. Missing ones stop `STEP: pr` with the list. A writer agent proposes the wording; the person approves it with the PR, not as a new gate.
3. Numbers the validator measured (test totals, file counts) are compared with the numbers the contract states; a difference is listed the same way.

### Project drift, as a maintenance mission

1. The plugin's method, as a brief: for each doc file, the claims it makes about the code (an option, a function, an example), each as `file:line`.
2. Every claim becomes a check that runs: an example executed, an option looked up in the source. A claim with no check is "not checkable", never "drift" (verification by execution, `ideas.md`).
3. The report lists failed checks only. Each becomes a ticket: fix the doc, or report the code as a bug for the person to label.

## Steps

1. The mission drift script. Test from eslint-10's records: it lists VAL-CONF-001 and VAL-TEST-001, and nothing else.
2. `STEP: pr` runs it.
3. One project drift mission on the gym's `docs/`, by hand, to see what it finds before anything is scheduled (P19 row 7).

## Outside check

- **Mission drift:** on eslint-10 it flags exactly the two stale values above. On deps-node-22, its flags match a list made by hand first.
- **Project drift:** 5 known mismatches planted in a copy of the gym's docs. It finds at least 4, and its false alarms on the untouched files are counted.

## Open questions for Rode

- Should mission drift stop `/pr`, or only warn?
- For a doc that is wrong, who decides between "fix the doc" and "the code has a bug"? (Draft: always the person, per finding.)

## Not doing

No scheduled drift run yet. No drift check on the factory's own docs in this step, though the roadmap page itself has drifted (see the November assessment).
