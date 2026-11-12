# P29. A patch stays inside its ticket: a scope check in code, flagged first, blocking once measured

**Status:** draft: wait for 10 flags (see the [November assessment](assessment-2026-11.md)) · **Effort:** S · **Depends on:** coverage.sh's path reader (D125); changes `patch-guard.sh`, so a "guard change"

## Problem

Nothing in code checks that a worker's patch stays inside its ticket.

- The worker brief says "Implement this ticket only" (`.factory/briefs/worker.md`, line 5). That is prose.
- `patch-guard.sh` checks protected paths, frozen paths and frozen tests, deleted tests, symbolic links, generated files, skips, silencing comments and secrets. It doesn't check the patch's files against the ticket.
- The reviewer judges scope only where a contract has a CROSS assertion for it.

Fix rounds are where scope drifts. The worker reads the verdict's [blocking] issues and acts on them (`worker.md`, line 4). The trusted-factory talk (Tessl, November 2026) reports exactly this: a review comment got an agent to change code outside the ticket. Our own record: in deps-node-22 ticket 01, the worker changed `test/server.test.js` with a `setImmediate`, which the ticket's categories didn't allow. The worker reported it itself, as a CONTRACT DOUBT. Nothing would have caught it otherwise.

## Design

1. **The ticket's files.** The paths the ticket names in backticks, read with the same pattern `coverage.sh` uses (D125), plus the files its covered assertions name. A ticket can widen this with a `## Files` section (globs) when it can't list files in advance.
2. **The check.** `patch-guard.sh` lists every file the patch adds, changes or deletes that matches none of them.
3. **Flag first.** The first version only reports: one `SCOPE` line in the integration log, the same line in the reviewer's brief ("these files are outside the ticket: judge whether each is needed"), and a count in `metrics.sh`.
4. **Block when measured.** After 3 missions, compare the flags with the reviewers' judgments. If at least 9 flags in 10 were real scope drift, the check blocks: the worker either stays in scope or stops with DECISION NEEDED. Otherwise the reader is fixed first.

## Steps

1. A test in `tests/factory.test.sh`: a ticket naming `lib/a.js`, a patch changing `lib/a.js` and `lib/b.js`: the guard prints `SCOPE: lib/b.js is outside ticket 01` and still passes. The same patch inside the ticket prints nothing.
2. The reviewer brief's line, and the metric.
3. After 3 missions, the measurement and the decision to block, as an ADR line.

## Outside check

- On deps-node-22's ticket 01 patch (from the run archive, if that round's patch was kept), the flag names `test/server.test.js` in the round where `setImmediate` was added.
- Over the next 3 missions: the share of flags the reviewer confirms (precision), and no scope drift that the reviewer later finds without a flag (recall).

## Open questions for Rode

- Flag only, or block from the start for fix rounds alone?
- Count test files the worker adds for its own ticket as in scope? (Draft: yes, under the test folders of the ticket's source files.)

## Not doing

No model judges scope in this step. The check is a list of files; the reviewer judges each flag.
