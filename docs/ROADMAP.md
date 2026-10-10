# Roadmap

From mission 1's retro and from ideas borrowed (never installed) elsewhere. One item per issue; `scripts/dev/open-roadmap-issues.sh` creates the open ones on GitHub (sections marked ✅ are skipped).

Sources: **M** mission 1 retro · **A** Addy Osmani's agent-skills · **P** pstack · **E** ECC · **N** new, from reviewing the flow.
Effort: S < half a day · M ≈ 1–2 days · L > 2 days.

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

## v1.1.0: code health and safety ✅

| # | Item | Src | Release |
|---|---|---|---|
| CH1 | Code steward (G5): whole mission diff vs a written quality bar, every changed file explained | N, you | ✅ 1.1.0 |
| CH2 | Health ratchet: duplication, size, nesting, debt markers, skipped tests, repo tool; never worse | N, E | ✅ 1.1.0 |
| S1 | Block destructive and check-skipping commands: live command guard + patch guard at integration | E, A | ✅ 1.1.0 (guard loading in pi-subagents children to confirm on mission 2) |
| F10 | Tickets by an agent, approved by you (and fix tickets from findings) | N | ✅ 1.1.0 |
| F11 | Size-aware routing (L → heavy worker) | M | ✅ 1.1.0 |
| C14 | Re-validate a failing behavior verdict once fixes are built | N | ✅ 1.1.0 |

## v1.2.0: practice packs ✅

| # | Item | Src | Release |
|---|---|---|---|
| P1 | Practice packs: content for a kind of software (api, batch, bot), `install-into.sh --pack` | N, you | ✅ 1.2.0 |
| X4 | Batch contract checklist (now the `batch` pack) | M, A | ✅ 1.2.0 |

## v1.3.0: contract quality and supervision

**Contract quality and fluidity**

| # | Item | Src | Why | Fix | Effort |
|---|---|---|---|---|---|
| C6 | Contract self-consistency | M | An outcome count contradicted another assertion and passed every judge | Critic mechanical checks: processed = succeeded + failed + deferred; one counting rule everywhere; Given = preconditions; regression fixture | M |
| C7 | Critic output format enforced | M | Emoji headings, no `[blocking]` tags | Strict template; `next.sh` lints the critique before G1 | S |
| C10 | Spec drift check before PR | M, N | Spec still described the old design after decisions | `STEP: pr` runs a fresh drift checker (spec ↔ contract ↔ tests ↔ README ↔ decisions.tsv) | M |
| F8 | Compact only between waves | E | Lead context growth | Playbook rule | S |
| F12 | Attack the premise at escalation | P | Real cause (too big) found by hand | Before round 3, log the shared premise of failed attempts; propose split / amend / heavy | S |
| F13 | Draft MR and CI status from the factory | N | MR created by hand, CI log photographed | Project token for `glab`; `/pr` opens the draft; failed jobs feed the fix lane | S |
| F15 | Starter kit ships the factory | N | Per-repo setup | New repos born with factory, CI include, commands.env, behavior-paths | M |

**Safety and supervision**

| # | Item | Src | Why | Fix | Effort |
|---|---|---|---|---|---|
| S2 | Intake scan of vendored skills | E | Third-party text becomes instructions for agents with bash | Scan upstream text before re-pinning; record in UPSTREAM.md | M |
| S3 | READY / NOT READY report | E | Evidence hard to read for a reviewer | Build / Lint / Tests / Secrets / Diff outside scope → READY | S |
| S4 | Learnings unreviewed until promoted | E, P | Retro items could silently become rules | Status column in decisions and retro; only a human promotes | S |
| S5 | Minimum bar for autonomy (Step 3 ADR) | E | Agents run with your identity | Sandbox, least agency, kill switch, no default egress, short-lived credentials | L |
| S6 | Security review role | A | Features that delete production data | `factory-security-reviewer` per mission, triggered by `.factory/security-paths`, another family | M |
| S7 | Install lifecycle | E | Multi-repo updates | `install-into.sh --dry-run`, `uninstall`; doctor warns on outdated `.factory/VERSION` | S |

## v1.4.0: proof and scale

| # | Item | Src | Why | Fix | Effort |
|---|---|---|---|---|---|
| X1 | Bot harness / verification skill | M, P | G4 only by human acceptance | Generated verification skill that drives the bot like a user; replay in CI | L |
| X2 | Skill evals with pass@k | A, E | Critic regressions found live | Fixtures per local skill, 3 runs, require 3/3 | M |
| X3 | Anti-rationalization tables | A | "Tests pass so the assertion holds" | Excuse/rebuttal tables in contract, critic, verify-behavior, worker | S |
| X5 | Reviewer does both axes inline | A, M | 3 agents per review under a small quota | Axes inline; axis agents only for L tickets | S |
| X6 | Interrogate panel for risky missions | P | Production deletes deserve more than one judge | Opt-in multi-family panel before `/pr` | M |
| X7 | Definition of Done | A | No standing bar across missions | `docs/agents/definition-of-done.md`, checked by gate and `/pr` | S |
| X8 | Rollout template in the MR | A | Rollout written by hand | Known limits (from labels), prerequisites, staged rollout, emergency stop | S |
| X9 | Mission intents beyond features | P, N | Only a feature path exists | Bugfix lane (reproduce → fix → verify), maintenance lane | M |
| X10 | Request accounting + quota case | M | 429s under a shared quota | Requests per role from run metadata | S |
| X11 | Model compatibility map + smoke | M | Thinking levels and reasoning replay found at run time | `.factory/model-compat.json` in models-lint; `/factory-smoke` | S |
| X12 | Dashboard, perf-analyst | N | Supervision at a glance; ops | Static dashboard from `.scratch/`; perf-analyst read-only on captured artifacts | L |

## After Step 2 is declared

| # | Item | Src | Why | Fix | Effort |
|---|---|---|---|---|---|
| X13 | Durable mission runner on Pi Durable | N | Step 3 needs unattended missions that survive crashes mid-wave, steering from phone or Slack, and per-agent sandboxed environments (S5) | A thin runner that loops on `next.sh` with Pi Durable checkpoints, execution environments and multi-client steering; scripts and files stay the source of truth. Wait for the API to settle. | L |

## Explicitly not taking

| Idea | Source | Why not |
|---|---|---|
| A second skill collection as router | A, P, E | Same-job skills override each other silently |
| Token optimizations | E | The bottleneck is requests per window, not tokens |
| Automatic learning from session hooks | E | Not Pi; auto-extraction from work sessions is a data question |
| Hosted apps | E | Code and history would leave your environment |
| Live forensics on production | P | Perf analysis stays on captured artifacts |
