# P28. Gate yield: what each gate catches, what it gets wrong, and what it costs the person

**Status:** draft, for review before the nightly loop builds it · **Effort:** M · **Depends on:** D97 (run archive), `metrics.sh`; complements P23 (recall on seeded faults)

## Problem

Our cost is the person's attention, not tokens. `metrics.sh --all` on the gym (2026-11-12, 5 missions, 4 merged):

| Measure | Value |
|---|---|
| Model cost per MR | $3.93 |
| Human interventions per MR (decisions plus hand commits) | 15.3 |
| First-pass reviews | 44% |

The trusted-factory talk (Tessl, November 2026) quotes $13 per PR after optimising, down from $75. We are already well under that. The 15.3 is the number to bring down, and we can't yet say which gate spends it, or what each gate buys us.

The talk can say what each stage catches: verification caught more than half of the bad fixes, review about a quarter. P23 measures recall on seeded faults. We don't measure what our gates do on real runs.

eslint-10 shows why that matters:

- **The critic** ran 6 rounds. Every finding was real, but found one at a time (see P26).
- **The reviewer** failed twice for process reasons and judged nothing. The first time it returned no output; the second time it stopped on a supervisor message (D132).
- **The patch guard** blocked once, wrongly: the deleted file was a config, not a test (D131).
- Of the mission's 11 decisions, 2 were the gates meant for people (G1 and ticket approval). The others came from these gates' misses and false alarms, plus the dependency step (P29).

## Design

For each gate (patch guard, test on base, lint and tests at integration, contract critic, reviewer, validator, health ratchet), for each mission:

| Column | From |
|---|---|
| runs | the archive (`run.json`) and the integration logs |
| caught | a FAIL or block followed by a change that passed (the next round's diff touched what the finding named) |
| false alarm | a FAIL or block that the next step overturned with no code change (a rereview that passed, a decision accepting it, a guard rule fixed afterwards) |
| no judgment | a run with no verdict or with all assertions unverified |
| decisions caused | the rows of `decisions.tsv` that cite the gate's file or round |
| cost | tokens and dollars of its runs |

Each decision also gets a cause class at the time it's logged: **gate** (a step meant for people), **gap** (the factory couldn't do it), or **error** (a factory or contract mistake). `human.sh` asks for it with a default.

The Health page shows the table, with "interventions per MR" and "gate" decisions per MR as the headline numbers.

## Steps

1. `metrics.sh gates <mission>`, computed from what exists: verdicts and their `.rN` copies, critiques per round, `integrate.log`, `decisions.tsv`, the archive. A test on a fixture mission built from eslint-10's records, its expected counts read from those records by hand first (the critic's rounds, the reviewer's runs with no judgment, the guard's one false alarm).
2. The cause class in `human.sh` (one optional word, default "gate").
3. The Health page panel.

## Outside check

- The table for eslint-10 matches what the person remembers of the mission. Rode reads it and finds no row wrong.
- After 3 more missions, the gate with the most "error" decisions is the one the nightly loop fixes first, and its count drops in the next 3.

## Open questions for Rode

- Is "interventions per MR" the right headline, or should "gate" decisions stay out of it, since they're meant for you?
- Target? (Draft: 5 per MR, the number the retros already use.)

## Not doing

No new gate, and no change to any gate's rules. This only measures them.
