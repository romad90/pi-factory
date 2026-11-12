# P32. Every hand touch is a learning event: fix the factory, not the feature

**Status:** draft, early: fix the hand-commit count first (see the [November assessment](assessment-2026-11.md)) · **Effort:** S · **Depends on:** D114 (learning loop), D89 (hand commits counted)

## Problem

The trusted-factory talk (Tessl, November 2026) puts the rule plainly: when the factory gets it wrong, fix the factory, not the feature. We do this, but only when the person thinks of it.

eslint-10 had three hand fixes. Each became a factory fix only because the person raised it in a conversation:

| Hand fix | Became |
|---|---|
| `test/.eslintrc.js` deleted by hand (the guard called it a test) | D131 |
| the reviewer stopped on a supervisor message; a rereview by hand | D132 |
| an amendment marked sent but never applied; a second amendment by hand | backlog B9 |
| ticket 02 merged into 01 by hand (the lint gate made the split impossible) | nothing yet |

The learning loop reads four kinds of event: guard refusals, lost rounds, lead deviations and human messages (`learn-records.mjs`, line 107). A hand commit, a hand edit to a ticket, a hand rereview or a hand state file is not an event. `metrics.sh` counts hand commits (D89), but nothing gives them a cause or brings them to the nightly loop.

## Design

1. **New event kinds** in `learn-records.mjs`:
   - `hand_commit`: a commit on the mission branch without the factory's trailer (`metrics.sh`'s D89 rule).
   - `hand_edit`: a ticket, contract or state file changed outside the factory's own commits (git log on `.scratch/<mission>/issues/`, `spec.md` outside amendments, `state/`).
   - `hand_step`: decisions of kind `rereview`, `deps`, or `decide` that answer a factory question (not a gate meant for people).
2. **A cause asked at the time.** `human.sh` already logs decisions. For a hand commit or edit, the next `next.sh` run lists the unexplained ones on one line ("2 hand changes since the last step: give a cause with `human.sh why <commit> <cause>`"). The cause is one of P30's classes (gate, gap, error) and a few words. It never blocks.
3. **The nightly loop codes them** like the other events: a `factory_bug` or `factory_gap` among them becomes work, as today.

## Steps

1. The three event kinds, with a test on a fixture mission built from eslint-10's records: 1 hand commit (the config deletion), 1 hand edit (the ticket merge), 2 hand steps (rereview, the guard decision).
2. `human.sh why`, and the one line in `next.sh`.

## Outside check

- On eslint-10's records, the extractor lists the four hand fixes above, and nothing the factory did itself.
- Over the next 3 missions, every hand fix the person mentions in a retro already has an event, so the retro finds nothing the loop didn't already see.

## Open questions for Rode

- Ask for the cause in `next.sh` (draft), or only in the retro?
- Should a hand edit to a ticket count as an intervention in the metrics, like a hand commit?

## Not doing

No blocking. A hand change is often the right move; the point is that it's seen.
