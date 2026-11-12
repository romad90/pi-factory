# Roadmap

From the missions' retros and records, and from ideas borrowed (never installed) elsewhere. Rewritten in November 2026 from the [assessment](proposals/assessment-2026-11.md) of what the code holds.

Sources: **M** mission 1 retro · **A** Addy Osmani's agent-skills · **P** pstack · **E** ECC · **N** new, from reviewing the flow.
Effort: S < half a day · M ≈ 1–2 days · L > 2 days.

**Larger changes** are discussed as [proposals](proposals/README.md) first: several gateways (P1), the lead as a script (P2), the maintenance lane (P3, the content of X9), director and triggers (P4), continuous improvement with pull requests (P5), a control room with a dashboard and events from operations (P6), a launch gate in a sandbox (P7), a hands-off mission with at most five human interventions (P8, next), rounds that converge (P9), a front page showing every subagent at every stage (P10), the factory installed once per machine (P11).

**Rule for borrowed ideas:** mattpocock/skills v1.3.1 stays the only skill foundation. Borrow an idea or a single skill, vendored, pinned and scanned. Never install a second skill router.

---

## v1.0.0: correctness and fluidity ✅

| # | Item | Src | Release |
|---|---|---|---|
| C1 | Rounds computed by script, verdict history kept | M | ✅ 1.0.0 |
| C2 | Model never self-reported | M | ✅ 1.0.0 |
| C3 | Worker run without patch = failed round | M | ✅ 1.0.0 |
| C4 | Patch path returned by the wave | M | ✅ 1.0.0 (to confirm against pi-subagents' result shape in mission 2) |
| C5 | Evidence or label (PASS with evidence, FAIL, UNVERIFIED) | M, P | ✅ 1.0.0 |
| C8 | Irreversible decisions never default | M, P | ✅ 1.0.0 |
| C9 | Decision log (`decisions.tsv`) | M, P, E | ✅ 1.0.0 |
| C11 | Gate in CI, not only local | M | ✅ 1.0.0 |
| C12 | Refuse to build without checks; extra check | M | ✅ 1.0.0 |
| C13 | Workflow passed by file | M | ✅ pre-1.0 |
| F1 | Fix lane with blast radius | M, P, E | ✅ 1.0.0 |
| F2 | Staleness scoped to behavior paths | M | ✅ 1.0.0 |
| F3 | One-word human gates | N | ✅ 1.0.0 |
| F4 | Automatic checkpoints | N | ✅ 1.0.0 |
| F5 | Pre-flight before every `/factory` | M, N | ✅ 1.0.0 |
| F6 | Notify on human steps | N | ✅ 1.0.0 (herdr "blocked" state still open) |
| F7 | Pause / pickup, auto-pause on context | P | ✅ 1.0.0 |
| F9 | Lead watchdog | M | ✅ 1.0.0 (playbook rule) |
| F14 | Factory install in its own MR | M | ✅ 1.0.0 |

## v1.1.0: code health, safety and practice packs ✅

| # | Item | Src | Release |
|---|---|---|---|
| CH1 | Code steward (G5): whole mission diff vs a written quality bar, every changed file explained | N, you | ✅ 1.1.0 |
| CH2 | Health ratchet: duplication, size, nesting, debt markers, skipped tests, repo tool; never worse | N, E | ✅ 1.1.0 |
| S1 | Block destructive and check-skipping commands: live command guard + patch guard at integration | E, A | ✅ 1.1.0 (guard loading in pi-subagents children to confirm on mission 2) |
| F10 | Tickets by an agent, approved by you (and fix tickets from findings) | N | ✅ 1.1.0 |
| F11 | Size-aware routing (L → heavy worker) | M | ✅ 1.1.0 |
| C14 | Re-validate a failing behavior verdict once fixes are built | N | ✅ 1.1.0 |
| P1 | Practice packs: content for a kind of software (api, batch), `install-into.sh --pack` | N, you | ✅ 1.1.0 |
| X4 | Batch contract checklist (now the `batch` pack) | M, A | ✅ 1.1.0 |

## Since v1.1.0 ✅

Built between 1.2 and 1.4.0-rc.78, from the proposals (the ADR has each decision):

| What | Decision |
|---|---|
| Models profile per machine (F16), monorepo projects (F17) | D55, D56 |
| Hands-off steps 1 to 3 (P8), rounds with a journal (P9) | D65–D70, D84 |
| The lead as a script, `run.sh` (P2): built, not yet used on a mission | D91 |
| Install once per machine (P11), setup by rehearsal (P18) | D92, D102 |
| Refactor and maintenance intents with frozen paths and tests (P3, X9) | D93, D96 |
| Run archive, scoring, benchmark (P14); tokens per run (X10) | D97, D98, D85 |
| Context repos (P13); jobs planned by an architect (P22's first step) | D99, D105, D109 |
| The learning loop and lessons between machines (P15's first form) | D114, D115 |
| The cockpit: inbox, timeline, run page, health, gate page, reports (P10, X12) | D119–D123, D130, D133 |
| Dependency lane, real paths in tickets, the critic's "Passes wrongly", Node check | D124–D127 |
| Fixes from the nightly loop | D128, D129, D131, D132 |

## Now: run missions and learn

Decided on 2026-11-12: nothing new is built until missions show which item is worth it. The [November assessment](proposals/assessment-2026-11.md) sorts every proposal and every item that was open here.

The measure that sorts them, on the gym: $3.93 of model cost per MR, 11 logged decisions per MR (13 planned gates and 31 unplanned over 4 MRs), 44% first-pass reviews. The person's attention is the cost.

| Next mission | Question it answers |
|---|---|
| get-port 5 to 7 | a third dependency mission: does the deps lane hold, and is P31 worth its guard decision? |
| a bug fix in `lib/` | gates on product code: first-pass rate, the reviewer's yield (P30) |
| docs against code on the gym | P34's project drift, by hand, before anything is built |
| any of them, run with `run.sh` | P2: does a scripted lead change the decision count? |

The nightly loop keeps fixing factory bugs from the records (its backlog is in the scheduled task, not here).

## Waiting on evidence

| Item | What would start it |
|---|---|
| P28 checklist packs, P33 contract angles | evidence in hand (eslint-10: 6 blocking findings over four rounds); the replay decides between them |
| P30 gate yield, P32 hand touches as events | early: they are the measure the rest waits on; the hand-commit count is fixed first |
| P34 drift report (was C10) | early for mission drift: two stale values are on the gym's master |
| P29 ticket scope check | 10 flags |
| P31 scripted install | Rode's guard decision |
| P23 seeded-fault bench (with X2) | 3 more missions |
| P20 token budget | a mission that stops on a token limit |
| P1 fallback chain | a mission that stops on a provider with another one free |
| P12 durable runner (was X13), P16 issue in, MR out (was F13) | P2 in use; `mr.sh` gets its GitHub path first |
| P19 proactive systems, P22 tiers | their entry criteria; P30's numbers |
| P21 security layer (with S6) | before a mission on production code that handles untrusted input |
| P24 code health loop | the first refactor mission |
| P7 launch gate, X8 rollout template | the first service that runs |
| One sandbox decision (S5, S8, X14) | before any unattended run on work machines |
| X1 bot harness | a mission that needs it |
| S2 intake scan of vendored skills | before the next skill re-pin |
| F12 attack the premise at escalation | the next escalation |

## Dropped or folded (November 2026)

| Item | Where it went |
|---|---|
| P4 director | the job (D105); triggers are P19 |
| P5 continuous improvement | P15 and P19 |
| P6 control room, hosted | dropped ("hosted apps" below); the dashboard is the cockpit |
| P17 plans that leave no decision | P33 and P34 |
| H1 human time ledger | P30 |
| C6 contract self-consistency | a P28 pack question |
| C7 critic output format | P33's merge script |
| S3 READY / NOT READY report | to check against `verify.sh` and the gate page, then drop |
| F8 compact between waves | moot with a scripted lead |
| F15 starter kit, S7 install lifecycle | replaced by install once (D92) |
| X3 anti-rationalization tables | D126's "Passes wrongly" rule |
| X5 reviewer does both axes inline | dropped: the opposite of P33, and requests per window no longer limit us |
| X6 interrogate panel | P33 |
| X7 Definition of Done | the quality bar and the code steward (CH1) |
| S4 learnings unreviewed until promoted, X11 model compatibility | done in practice (decisions marked unreviewed; `models-probe.mjs`, D59) |

## Explicitly not taking

| Idea | Source | Why not |
|---|---|---|
| A second skill collection as router | A, P, E | Same-job skills override each other silently |
| Token optimizations | E | The bottleneck is requests per window, not tokens |
| Automatic learning from session hooks | E | Not Pi; auto-extraction from work sessions is a data question |
| Hosted apps | E | Code and history would leave your environment |
| Live forensics on production | P | Perf analysis stays on captured artifacts |
