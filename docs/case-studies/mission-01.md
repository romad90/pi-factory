# Case study: mission 1

The first real mission run through the factory (pre-1.0, October 2026). Names, systems and internal details are anonymized; the mechanics and numbers are real.

## The feature

A scheduled **batch bot** that finds expired records in an upstream system and cleans them up, with a dry-run mode, caps, and a report. A production-facing change that deletes data. The kind of feature where an agent guessing wrong is expensive.

- Spec: 25 user stories (too many; see lessons).
- Contract: about 20 assertions, `VAL-<AREA>-NNN`, written by the author agent and attacked by a critic on another model family.
- Instrument: 22 behavior scenarios, hidden from workers.
- Tickets: 6 planned, 9 at the end (fix tickets added mid-mission).
- Result: gate PASS, MR merged with green CI.

## Decisions the human made (and where they lived)

| Decision | Chosen | Why it mattered |
|---|---|---|
| Upstream 5xx or timeout during a run | Stop the run; report the rest as deferred, "stopped after upstream failure" | The contract first said "continue", which would hammer a failing service |
| Other 4xx on one item | Continue with the next item | One bad record shouldn't stop the batch |
| 409 on delete | Counts as succeeded | Already gone is the desired end state |
| Exit codes | 0 ok, 1 partial, 2 config, 3 dependency, 4 unexpected | Schedulers and alerts read them |
| Dry-run at first deploy | On in **all** environments | The first amendment made pre-prod and prod inconsistent |
| Where the guardrails live | Deployment chart values (env), not the secret store | A worker had picked the secret store after a question timed out |
| App name | Lower-case, hyphenated everywhere | The chart lint in CI rejected the old name (RFC 1123) |

All of these lived only in chat during the mission. In v1.0.0 they go to `decisions.tsv` (D43).

## What went well

- **Generated briefs and brief ids.** No hand-written dispatch happened.
- **Family separation paid off.** The critic caught a missing cap and an inconsistent assertion before any code existed.
- **The integration gate held.** The lead refused to commit a change it didn't make.
- **Escalation routing worked once the round was recorded.** The heavy worker took over ticket 04 by itself.
- **The stops at human steps were all correct.**

## What went wrong, and what v1.0.0 changed

| Problem | Evidence | v1.0.0 |
|---|---|---|
| A worker run without a patch didn't count as a round | Ticket 04 needed a hand-written verdict to escalate | `record-no-patch.sh` (D38) |
| Rounds and metrics could lie | "Round 1" after 2 failed runs; "100% first-pass" | Rounds from history (D38) |
| Verdicts named a model that wasn't used | All verdicts said one vendor's model | Configured model written by `collect.sh` (D39) |
| The lead searched temp folders for patches | Handoff manifests found by hand | Patch path returned by the wave (D39) |
| Every behavior assertion passed without a harness | Interim validation reported all PASS | Evidence or label; human acceptance (D40) |
| A worker proceeded on a timed-out question | Picked the secret store against the spec | Irreversible choices never default (D47) |
| A three-line chart fix had no proper lane | Committed outside any gate | Fix lane (D41) |
| Any small change invalidated the behavior verdict | Re-validation for a values tweak | Staleness scoped to behavior paths (D42) |
| The approval line was typed by hand; decisions lived in chat | Several hand edits of `spec.md` | One-word gates + `decisions.tsv` (D43) |
| `commands.env` empty would have let integration skip tests | The lead blocked on it by luck | No integration without tests (D44) |
| Chart lint only ran in CI | Red pipeline after the gate passed | `FACTORY_EXTRA_CMD` (D44) |
| VPN drop → 7 connection errors | One failed wave | Pre-flight (D46) |
| `checkpoint.sh` run by hand about 10 times | | Automatic checkpoints (D46) |
| Watching the screen during waves; restarts after a lead loop | | Notifications, pause/pickup, watchdog (D45) |
| The feature MR carried 193 files, mostly tooling | | Install in its own MR (D48) |
| The gate only ran locally | MR said so | Includable CI template (C11) |
| Scripts pasted inline into the subagent tool | A red band on every wave | Workflows passed by file (pre-1.0, kept) |

## Lessons for mission 2

1. **Split specs above roughly 12 stories.** 25 made the contract and G1 long.
2. **Keep core tickets small.** The efficient worker passed three small tickets and failed the core one twice. Ticket size matters more than the model.
3. **Default assertions to `Kind: code` until a harness exists.** Behavior assertions without a harness only produce labels.
4. **Use a batch-bot checklist, not a conversational one.** Prompt injection and tone don't apply to a batch job; exit codes, idempotency, partial failure, caps and dry-run do. (Now the `batch` pack, v1.1.0.)
5. **Check the contract's arithmetic.** One assertion counted outcomes differently from another, and it passed the critic, eight reviews and the validator. (Roadmap C6.)

Full findings: [docs/retros/mission-01.md](../retros/mission-01.md).
