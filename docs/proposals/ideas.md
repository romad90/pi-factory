# Ideas to borrow

Ideas seen in other agentic tools, worth building our own way. We adopt none of these tools: the factory keeps its loop, its state (files in git) and its gates, and depends on nothing it can't replace. An idea moves from here into a proposal when it's picked.

Read from their public pages in October 2026; what they claim was not verified.

## From OpenCode Swarm (OpenCode plugin, MIT)

| Idea | What we'd build | Fits |
|---|---|---|
| Cross-project knowledge file | A shared, append-only knowledge file across a team's repos: lessons that apply beyond one repo (a lint pitfall, a provider quirk) | P5 journal, P4 director |
| Repository graph | A dependency graph of modules, saved in the mission folder, used to scope a refactor and the mutation gate | P3 dossier |
| Offline static security scan as a gate | A deterministic SAST check next to lint and tests, on the patch only | G4/G5 |

## From Factory (Droids)

| Idea | What we'd build | Fits |
|---|---|---|
| Agent readiness score per repo | A score of how ready a repo is for the factory: tests runnable, lint clean or baselined, behavior frozen, docs and glossary present, commands configured. Tracked over time | P3, P6; the first thing to show a team before installing |
| Living wiki per repo | The P3 dossier and `docs/` regenerated when the code changes, so documentation doesn't rot | P3, P5 |
| Model routing per task | Pick the model per task by quality, speed and cost, not only per role | P1 chains |
| Review on every pull request | The light review lane, triggered on every merge request | P4 first trigger |
| Mission control, usage analytics | Live missions, workers and logs; consumption per team and developer | P6 dashboard, P1 `usage.tsv` |

## From Port (internal developer portal, "agentic SDLC")

| Idea | What we'd build | Fits |
|---|---|---|
| Context from the existing catalog | Read service ownership, dependencies and environments from the team's catalog instead of rediscovering them | P3 discovery, P6 |
| Registry of agents, skills and MCP servers | An inventory of what each repo installs, checked against the team's standards (like `models-lint` for skills) | install, doctor |
| Bulk changes across services | One change (a runtime upgrade) planned once and run as one mission per repo | P4 cross-repo |
| Self-healing incidents, auto-fix of pipeline failures | Already in P4 and P6; confirms the order: fix lane first, incidents last | P4, P6 |
| Delivery metrics as the measure of value | Deployment frequency, lead time, change failure rate, recovery time per repo, before and after the factory | P6 dashboard, INTENT |

## From Anthropic's public skills (Apache-2.0)

| Idea | What we'd build | Fits |
|---|---|---|
| Measure a skill against a baseline (skill-creator) | Every change to an agent prompt, brief or skill is run on the same set of tickets with and without the change, graded on assertions, compared blind by a third agent. Mission 2's amendments (lint, `vi.spyOn`, frozen `src/`) were guesses; this makes them measured | all agents; a `factory-evals/` set built from past missions' tickets |
| Spot assertions that never discriminate | The analysis pass flags assertions that pass with or without the change, and flaky ones (high variance). Applies to our review assertions (VAL-) too | G4, review |
| Progressive disclosure | An agent sees a short description always, the full instructions only when needed, and runs bundled scripts as black boxes ("run `--help` first, don't read the source"). Smaller briefs, fewer tokens | worker brief, token budget |
| Server lifecycle helper for checks (webapp-testing) | One helper that starts the service, waits until ready, runs the check, stops it. "Reconnaissance then action": observe the running state before asserting | P7 launch gate |
| Targeted questions at the end of a deliverable (discernment-nudge) | Every report that reaches a human gate ends with two or three questions tied to its content: which claim to verify, which assumption to question, what context is missing. Fights approval by fatigue | human gates, review, "contract differences" |
| Reader test of a document (doc-coauthoring) | A fresh agent with no context reads the dossier or glossary and answers questions from it; what it can't answer is a gap | P3 dossier, docs tickets |
| Factory state as an MCP server (mcp-builder) | Mission status, human queue and decisions exposed as tools, readable from any client | P6 control room |

## From Claude Code's own mechanics

| Idea | What we'd build | Fits |
|---|---|---|
| Hooks on stop and on tool use | A stop hook refuses to end the lead's turn without a tool call or a human step (finding 34); a pre-tool hook enforces frozen paths before a write, not after a patch | lead, P7 least privilege |
| Tool allowlist per agent | Each role declares the tools it may call; anything else is refused by the runtime, not by the prompt | P7 least privilege |
| Checkpoints and rewind | A ticket or mission rolled back to a named checkpoint in one command, with its verdicts and markers | `reset-ticket.sh` (finding 31) |
| Context compaction | The lead's history summarized at a threshold instead of a manual "new session" | lead, until P2 removes the LLM lead |
| A task list visible beside the work | The mission's ticket table as a live list | P6 dashboard |

Skills we already use in the session and that map to lanes: code review (review lane), debugging (fix lane), deployment checklist with rollback triggers (P7), incident response and postmortem (P6 incident lane), tech debt scoring (P5 strategist), testing strategy (P3).

## From Machinist (AI software factory)

| Idea | What we'd build | Fits |
|---|---|---|
| Handoff notes between runs | A short journal each round leaves for the next | P9 step 2 |
| No-progress detection, token log | Escalate when a round fails like the last one; `usage.tsv` per round | P9 step 3, P1 |
| Provisioning check before spending tokens | The pre-flight proves every agent's model answers with tool calls before the first wave | `doctor.sh`, P1 |
| Typed stage results | Every stage returns JSON: outcome, verdict (including `human_decision_needed`), findings. Scripts read fields, never prose | collect, P2 |
| Read-only judges, enforced | `models-lint` refuses a reviewer or validator with write tools | D31, P7 least privilege |
| Risk-gated auto-approval | A docs-only or test-only change below a size limit skips a human gate | P8 |
| A "needs you" inbox | One list of everything waiting on the human, across missions | P8 step 4, P6 |

## From afonsoft/skills (spec-driven skills, MIT)

| Idea | What we'd build | Fits |
|---|---|---|
| Red loop before any fix | Fix rounds reproduce the failure first (`REPRO:`) | P9 step 1 |
| Diagnostic journal, three-strike rule | Journal per ticket; clustered failures question the contract, not the code | P9 steps 2 and 4 |
| Rationalization tables | The excuses an agent gives itself, with the right action, in the briefs | P9 step 5 |
| Risk tiers with a checkable list | T1 = at most 3 files, no logic change, no new dependency, one `git revert`, a deterministic check: approved automatically | P8, with Machinist's risk gate |
| Session summary on exit | Decisions, delivered, remaining, lessons, written by a script at `pause` or end of run | `pause.sh`, P8 morning summary |
| Agent self-debug table | Known failure patterns of an agent run (loop, context bulk, 429, stale state) with the check for each | `doctor.sh`, P2 |

Not taken: its orchestrator is a 575-line prompt a model follows, with state in a file the model edits, the design P2 moves away from.

## From the October 2026 scan of open-source factories

Ten projects picked from [awesome-software-factories](https://github.com/pungme/awesome-software-factories) for being closest to ours (deterministic control, gates, or a page showing agents at work), plus one suggested by the user. Read from their code (cloned, not run); star counts could not be fetched.

| Project | What it is | Idea for us | Fits |
|---|---|---|---|
| [DoorDash agentic-orchestrator](https://github.com/doordash-oss/agentic-orchestrator) (Apache-2.0) | Go server and desktop app; fixed phases from idea to PR | Progress is measured, not claimed: a round counts only if blockers drop or the worktree fingerprint changes; stop after 3 without progress, with a typed outcome. At 60% context the worker writes `progress.md` and a fresh session continues. The harness writes the verification report, never the agent | P9 step 3, P2 |
| [Symphony](https://github.com/openai/symphony) (Apache-2.0) | Spec and Elixir reference; the issue tracker is the control plane | Stall = no agent event for N seconds, not total time; typed end reasons (succeeded, failed, timed out, stalled); one snapshot for page, API and terminal; "the dashboard is never needed for correctness" | P10, worker timeouts |
| [Gas Town](https://github.com/gastownhall/gastown) (MIT) | Go; a mayor agent dispatches fleets of workers | Model escalation table (after N failures, move up a model, with a cap); stuck-agent detection by ping; last-activity colours per worker | P1 chains, P10 |
| [Super Simple Software Factory](https://github.com/disler/super-simple-software-factory) (MIT) | Deterministic Python owns the graph, agents are bounded nodes, runs on **Pi** | Every phase starts as failed and must earn success; agents return a typed envelope (status, summary, artifacts, notes for the next agent) checked by code; a malformed answer or failed gate is corrected in the same session; a write allowlist checked by fingerprinting the repo before and after | P2, P9 |
| [Anneal](https://github.com/mosonlab/anneal) (MIT) | Chains of agents plan, review, implement, merge; drives **Pi** | Isolated Pi launches (`--no-skills --no-context-files --no-prompt-templates`, a fresh config folder per run, a pre-flight on `pi --help` for required flags); stall timeout from the last JSON event; two reviewers of different families, one blind to the other; one settlement step that answers every finding instead of review loops | worker launch, P9, review lane |
| [Atelier](https://github.com/duanecilliers/atelier) (MIT) | Python engine on SSSF and a Next.js cockpit | SQLite trace (sessions, phases, events, envelopes, gate results) read by the page with a row cursor; gates that check claims (`diff_matches_claims`, `artifacts_exist`); a fresh builder resumes from a diff handoff | P10, P9 |
| [sgai](https://github.com/sandgardenhq/sgai) (MIT) | Go server, React page, one coordinator agent | Signal-then-refetch: a payload-less SSE `reload`, then one state fetch, with polling fallback | P10 |
| [Mastra Factory](https://github.com/mastra-ai/softwarefactory-template) (Apache-2.0) | A board of stages with rules; LLM workers | Stages as data (kind, role, action on entry); deterministic health findings with evidence and a suggested repair; human approvals as proposed decisions; optimistic revisions so a step can't run twice | P2, P10, P8 |
| [software-factory (nicolasmelo1)](https://github.com/nicolasmelo1/software-factory) (MIT) | Rust rules engine, not an orchestrator | Every rule written twice, prose and check, and each check has a fixture proving it fires; existing violations frozen with a review date (our lint baseline, generalised); evidence hashes recomputed, never trusted | patch guard, resolver, P2 |
| [Bernstein](https://github.com/sipyourdrink-ltd/bernstein) (Apache-2.0) | Deterministic scheduler for many CLI agents | Completion checked by typed signals, not the agent's word; heartbeat files; time limits by task size; retry 1 raises effort, retry 2 a stronger model; a hash chain over the audit log | P9, P1, `decisions.tsv` |
| [zazencodes software factory for Claude Code](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code) | One skill, seven subagents, markdown files; spec → build → four parallel reviewers (security, UX, UI, code) → approver | A dashboard with no server: one static `dashboard.html` reading job folders and first lines of verdict files, polling every 2 s, cards across stage columns, review chips that fill in; every agent writes only its own file and its first line is the verdict; an approver with an explicit escalate list (money, auth, deploy or CI, schema, a new dependency, a business decision) | P10, P8 risk tiers |

What they agree on, and what it says about us:

- **The control plane is code.** The projects that work with several models (SSSF, Atelier, Anneal, DoorDash, Bernstein, Mastra) all keep the loop in code. The ones with an LLM coordinator (Gas Town's mayor, sgai, Symphony's prompt-driven stages) assume a frontier model. Our gateway models make P2 more urgent, not less.
- **No agent reports its own success.** Envelopes, typed signals, recomputed evidence: success is something code observes. Our integrate gate already works this way; the lead's report and the worker's "self-check PASS" do not yet.
- **Stalls are about silence, not duration.** Time since the last event, not since the start.

Not taken: LLM coordinators (Gas Town, sgai, Symphony's routing by prompt), heavy stacks (Postgres, Redis, Electron, OpenTelemetry), merge trains and signed receipts. They answer a team's scale, not a file-in-git factory's.

## From Factory Missions (announcement and screenshots, October 2026)

Read from the [announcement](https://factory.com/news/missions) and the screenshots the user shared; the product is closed, so these are ideas, not code.

| Idea | What we would do | Fits |
|---|---|---|
| **Mission Control is one screen per mission**: the active feature with its preconditions and expected behavior, a features checklist (16/22), a progress log, the active worker with its live tool calls, tokens and time, keys to switch views | The cockpit's mission view takes this layout. Ticket = feature, `## Assertions` = expected behavior, `Blocked by` = preconditions; the live worker pane reads the run's last events and `usage.tsv` (D85) | P10, cockpit |
| **Milestones, each closed by a validation phase** | A mission splits into waves that end in a check, not only one validate at the end: after each wave, the contract assertions it covers are run. Catches a drifting mission at wave 2, not at the end | P9, P8 |
| **Planning is a conversation (`/enter-mission`), then the human acts as project manager** | Our interview already does this; the new part is naming the human's job after it: answer questions, approve gates, nothing else. That is P8's five interventions, stated as a role | P8, CHEATSHEET |
| **Skills learned from repeated work** (observe, learn, encode) | The retro's "three times, automate" rule, run by the factory: a pattern seen in three journals (D84) or three decisions becomes a proposed resolver rule or brief line, for the human to accept | P5 |
| **A model per role, chosen per strength** (a research model, a coding model, a validator) | Already ours (`runs.tsv` records models per role, D77); worth adding the family-diversity rule for validators to the onboarding | done, P11 |
| **Mission length is reported** (median about 2 hours, some over a day) | `metrics.sh` adds the mission's wall time and time waiting on the human, the two numbers that say whether P8 holds | metrics |
| **Commands classified by risk; secrets scanned** | The patch guard already blocks frozen paths; add a short list of commands a worker never runs (push, deploy, package publish) checked in the gate | patch guard, P8 risk tiers |

Not taken: the hosted control plane, OpenTelemetry export, enterprise admin. Same test as below: it must keep working if the vendor disappears.

## What to watch for

Each of these tools keeps something we don't want to give away: the runtime (OpenCode Swarm needs OpenCode), the hosted control plane and its data (Factory, Port), or a maintainer we depend on. The test for anything we take: does it keep working if that vendor disappears tomorrow?

## Sources

- [OpenCode Swarm](https://swarmai.site)
- [Factory](https://factory.com/), [SiliconANGLE on Factory's Droids](https://siliconangle.com/2025/09/25/factory-unleashes-droids-software-agents-50m-fresh-funding/)
- [Port](https://www.port.io)
- [Anthropic skills repository](https://github.com/anthropics/skills)
- [Machinist](https://github.com/owainlewis/machinist)
- [afonsoft/skills](https://github.com/afonsoft/skills)
