# Retro: mission 1

Factory findings from the first mission (a batch bot feature; anonymized). One file per mission. Add findings **while** a mission runs, fix them in this repo after the MR, then propagate with `install-into.sh`.

Priority: **P1** blocks or wastes a lot · **P2** friction · **P3** nice to have. **Status** points to the release or roadmap item.

## Orchestration

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 1 | A worker run that ends without a patch doesn't count as a failed round, so escalation never triggers | Ticket 04: two runs ended on a thinking-only turn; the round-2 verdict was written by hand | `record-no-patch.sh` | P1 | ✅ 1.0.0 (C3) |
| 2 | No way to rerun the contract wave after G1 findings | `workflow.sh contract` passed by hand | `/factory-amend` | P1 | ✅ 1.0.0 (F3) |
| 3 | Core tickets too big for the efficient worker | 01–03 passed, 04 (core) failed twice | Size tags + ticket writer | P2 | ✅ 1.1.0 (F10, F11) |
| 4 | The lead's context keeps growing | 57% after 4 tickets | Auto-pause above about 70% | P2 | ✅ 1.0.0 (F7) |
| 5 | Scripts run by hand with `!` instead of through the lead | `workflow.sh` printed, never executed | Cheat sheet rule | P3 | ✅ cheat sheet |
| 16 | Verdicts self-report a model that wasn't used | Every verdict named the same vendor model | Configured model written by `collect.sh` | P1 | ✅ 1.0.0 (C2) |
| 17 | Red band on every wave: script pasted inline | "workflow: true needs one fenced block" | Workflow written to a file, passed by path | P1 | ✅ pre-1.0 (C13) |
| 18 | VPN drop → a burst of connection errors | 7 × "Connection error" | Pre-flight with gateway check | P2 | ✅ 1.0.0 (F5) |
| 19 | Lead stuck in a repetition loop | "20.20.20…" burned quota | Watchdog rule in the playbook; steadier lead model | P2 | ✅ 1.0.0 (F9, partial) |
| 20 | Round written by the agent, not computed | "Round 1" after failures | Rounds from history | P1 | ✅ 1.0.0 (C1) |
| 21 | Patch located by hand in temp folders | Handoff manifest searched manually | Patch path from the wave, `locate-patch.sh` | P1 | ✅ 1.0.0 (C4) |
| 22 | Answered supervisor request still shown as open | Red band on a closed request | Decisions recorded and closed by `human.sh` | P3 | ✅ 1.0.0 (C9) |

## Contract

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 6 | The critic ignores the output format | Emoji headings, no `[blocking]` tags, no traceability table | Strict template + `next.sh` lint | P1 | roadmap C7 |
| 7 | Behavior written in **Given** | "4th and 5th not attempted" in a Given | Given = preconditions only | P2 | roadmap C6 |
| 8 | Conversational-bot checklist used for a batch bot | Irrelevant "Not covered" lines | `contract-checklist-batch.md` | P2 | roadmap X4 |
| 9 | Almost every assertion `Kind: behavior` with no harness | Contract | Default `Kind: code` until a harness exists | P2 | roadmap C6 |
| 10 | 25 user stories → long contract and G1 | Spec | Split above about 12 stories | P3 | ✅ cheat sheet |
| 23 | Contract self-contradiction passed every judge | One assertion counted succeeded = 3 instead of 4; the code was right | Mechanical consistency checks in the critic + regression fixture | P1 | roadmap C6 |

## Setup, models, integration

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 11 | Empty `commands.env` → integration without checks | Lead blocked on a dirty file | Refuse to build without tests | P1 | ✅ 1.0.0 (C12) |
| 12 | Shared quota: about 10 requests per window | 429 on the first parallel test | Retry block, concurrency 1; next: request accounting | P1 | ✅ partial; roadmap X10 |
| 13 | Model compatibility discovered at run time | Thinking level rejected, replayed reasoning rejected, `fallbackModels` removed | Compat map + smoke command | P2 | ✅ lint for `fallbackModels`; roadmap X11 |
| 14 | "Structured acceptance report not found" marker on every run | Smoke test | Check if acceptance can be disabled for factory agents | P3 | roadmap |
| 15 | Paths with spaces and `&` break unquoted commands | "not a git repo" | Quote everything; cheat sheet note | P3 | ✅ |
| 24 | Chart lint not part of integration | Red CI after a green gate | `FACTORY_EXTRA_CMD` | P2 | ✅ 1.0.0 (C12) |
| 25 | No lane for a small fix during or after a mission | Chart rename committed outside any gate | Fix lane | P1 | ✅ 1.0.0 (F1) |

## What worked (keep)

- Generated briefs and brief ids: no hand-written dispatch.
- Family separation: the critic caught a missing cap and flagged an inconsistent assertion.
- `integrate.sh` and the lead refusing to commit a change it didn't make.
- Escalation routing once the round was recorded.
- Every stop at a human step was correct.
