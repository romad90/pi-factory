# Assessment after eslint-10 (November 2026)

Six missions have run on the gym; four merged. This page sorts every proposal (P1 to P34; P26 and P27 exist only in the ADR) and every open roadmap item into four piles: **done**, **keep** (with what would start it), **fold** (into another item) and **drop**. It decides nothing: each line is a recommendation for Rode.

## The measure that sorts them

`metrics.sh --all` on the gym, 2026-11-12:

| Measure | Value |
|---|---|
| Model cost per MR | $3.93 |
| Logged decisions per MR | 11 (44 over 4 MRs): 13 planned gates, 31 unplanned |
| First-pass reviews | 44% |
| Rounds per ticket | 2.4 |

Tokens are cheap; the person's attention is not. An item earns its place by removing unplanned decisions or lost rounds, or by measuring them. The hand-commit count is broken (it runs on the target branch after a squash merge, where the factory's trailers are gone), so it is left out here.

Rode's rule for now (2026-11-12): build nothing new; run missions and learn. So "keep" means "wait for evidence", and each line says which evidence.

Status is read from the code (`scripts/factory/`, the ADR), not from the proposals' own status lines, several of which are stale.

## Proposals

| # | Proposal | In the code today | Pile | Why, or what would start it |
|---|---|---|---|---|
| P1 | Several gateways, fallback | probe per provider (D59, D79); no fallback chain | keep, later | start when a mission stops on a provider with another one free |
| P2 | The lead becomes a script | `run.sh` (D91) | **done**, unused | the gym still runs an LLM lead. Next mission: run it with `run.sh` and compare decisions |
| P3 | Maintenance lane | intents with frozen paths and tests (D93, D96) | **done** | close |
| P4 | Director and triggers | jobs planned by an architect (D105, D109); no triggers | fold | the director is the job; triggers are P19 |
| P5 | Continuous improvement | nothing of its own | fold | into P15 (the nightly loop) and P19 |
| P6 | Control room | the cockpit is local | **drop** the hosted part | the roadmap's own "not taking" list refuses hosted apps; the dashboard is the cockpit (P10); operations events are P19 row 5 |
| P7 | Launch gate, sandbox | command and patch guards; no OS sandbox | keep, later | start with the first mission on a service that runs; the sandbox part joins S8 |
| P8 | Hands-off mission | steps 1 to 3 (D65 to D70) | **done** to step 3 | step 4 is P30's number |
| P9 | Rounds that converge | journal, reproduce first (D84) | **done** | close |
| P10 | Front page | cockpit, gate page, reports (D119 to D123, D130, D133) | **done** | gate pages for tickets and verdicts when a mission asks |
| P11 | Install once | `onboard.sh` (D92) | **done** | close |
| P12 | Durable runner | nothing | keep, later | needs P2 in use first |
| P13 | Context repos | `context.sh` | **done** | close |
| P14 | Measure and improve | archive, score, bench (D97, D98) | **done** | close |
| P15 | The factory improves itself | `learn-loop.sh` and the nightly task | keep, **running** | it is the loop; judge it by merged nightly PRs |
| P16 | Issue in, MR out | `mr.sh` for GitLab only | keep, later | first the GitHub path (backlog B5); intake after P2 is in use |
| P17 | Plans that leave no decision | `readiness.sh` (D28) | fold | its drift section is P34; "measure first" is P33's grounding angle |
| P18 | Setup by rehearsal | `setup.mjs` (D102) | **done** | close |
| P19 | Proactive systems | nothing; the nightly task is its row 8 | keep, later | entry criteria unchanged; rows 1 and 7 wait on P31 and P34 |
| P20 | Token budget | `tokens.sh` (step 1) | keep, **low** | cost is $3.93 per MR; start only if a mission stops on a token limit again |
| P21 | Security layer | nothing | keep, later | start before the first mission on code that handles untrusted input in production |
| P22 | One entry, derived tiers | job planning (D105) | keep, later | needs P30's numbers to set tiers |
| P23 | Gates that can't be fooled | principle applied piecemeal (D125 to D127, D131, D132); no recall bench | keep | its measuring half is P30; the seeded-fault bench after 3 more missions |
| P24 | Code health loop | queued | keep, later | start with the first refactor mission |
| P25 | First job findings | must-fixes 1 to 6 (D113) | **done** to 6 | re-read the queued rest against the nightly backlog; drop what it already covers |
| P26, P27 | Learning loop, lessons between machines (no proposal page) | `learn-loop.sh`, `learn-export.sh` (D114, D115) | **done** | they are P15's first form |
| P28 | Checklist packs | the slot exists; no pack | keep, **first** | evidence in hand (eslint-10). It is P33's adversary list, so build them together or P28 alone first |
| P29 | Ticket scope check | nothing | keep | 1 flag in 7 commits, a false alarm: wait for 10 flags |
| P30 | Gate yield | nothing | keep, **early** | it is the measure everything else here waits on |
| P31 | Scripted install | nothing | keep | Rode's guard decision; evidence is 3 dependency decisions |
| P32 | Hand touches as events | nothing | keep, **early** | fix the hand-commit count first |
| P33 | Contract angles | one critic | keep | replay on eslint-10 decides between it and P28 alone |
| P34 | Drift report | nothing | keep, **early** for mission drift | two stale values are on the gym's master today |

## Open roadmap items

`docs/ROADMAP.md` stops at v1.3.0; the factory is at 1.4.0-rc.78. Its open items, sorted the same way:

| # | Item | Pile | Why |
|---|---|---|---|
| H1 | Human time ledger | fold into P30 | same question, counted in decisions |
| C6 | Contract self-consistency | fold into P28 | a pack question |
| C7 | Critic output format enforced | fold into P33 | the merge script and the `not run` status; B6 in the nightly backlog |
| C10 | Spec drift check before PR | fold into P34 | same item |
| F8 | Compact only between waves | drop | moot once the lead is `run.sh` |
| F12 | Attack the premise at escalation | keep, small | D84's journal does half; ask again at the next escalation |
| F13 | Draft MR and CI status | fold into B5 | `mr.sh` exists; GitHub path missing |
| F15 | Starter kit ships the factory | drop | replaced by install once (D92) |
| S2 | Intake scan of vendored skills | keep, small | still true, still cheap; before the next skill re-pin |
| S3 | READY / NOT READY report | check, then drop | `verify.sh` and the gate page may already cover it |
| S4 | Learnings unreviewed until promoted | **done** in practice | decisions carry "unreviewed"; nightly PRs need Rode's merge |
| S5, S8, X14 | Autonomy bar, OS sandbox, micro-VM | keep as one item, later | one sandbox decision, with P7; before any unattended run on work machines |
| S6 | Security review role | fold into P21 | same item |
| S7 | Install lifecycle | drop | replaced by D92; doctor already warns on the version |
| X1 | Bot harness | keep, later | `docs/agents/bot-harness.md` exists; no mission has needed it |
| X2 | Skill evals with pass@k | fold into P23 | the recall bench |
| X3 | Anti-rationalization tables | drop | D126's "Passes wrongly" rule did the job for the critic |
| X5 | Reviewer does both axes inline | drop | the opposite of P33; requests per window is no longer the limit |
| X6 | Interrogate panel | fold into P33 | several angles |
| X7 | Definition of Done | drop | the quality bar and the code steward (CH1) are it |
| X8 | Rollout template in the MR | keep, later | with P7, for a service that deploys |
| X10 | Request accounting | **done** | `usage.sh`, `tokens.sh` (D85) |
| X11 | Model compatibility map | **done** | `models-probe.mjs`, doctor (D59) |
| X12 | Dashboard | **done** | the cockpit |
| X13 | Durable mission runner | fold into P12 | same item |

## What this leaves

- **Done, to close:** P3, P9, P11, P13, P14, P18, and P2, P8, P10, P25 to the step named.
- **Dropped or folded:** P4, P5, P6 (hosted part), P17, and 15 roadmap items.
- **Waiting on evidence:** 18 proposals. The four marked first or early (P28, P30, P32, P34) are the ones whose evidence is already in the gym's records.
- **One page instead of two:** the roadmap and the proposals' status lines disagree with the code in many places (the tables above list them). If Rode agrees with the piles, `ROADMAP.md` is rewritten from this page and the proposals' status lines are corrected.

## What the next missions should tell us

| Mission | Question it answers |
|---|---|
| get-port 5 to 7 | a third dependency mission: does the deps lane hold, and is P31 worth its guard decision? |
| a bug fix in `lib/` | gates on product code: first-pass rate, the reviewer's yield (P30) |
| docs against code on the gym | P34's project drift, by hand, before anything is built |
| any of them, run with `run.sh` | P2: does a scripted lead change the decision count? |
