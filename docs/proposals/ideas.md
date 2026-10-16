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

## What to watch for

Each of these tools keeps something we don't want to give away: the runtime (OpenCode Swarm needs OpenCode), the hosted control plane and its data (Factory, Port), or a maintainer we depend on. The test for anything we take: does it keep working if that vendor disappears tomorrow?

## Sources

- [OpenCode Swarm](https://swarmai.site)
- [Factory](https://factory.com/), [SiliconANGLE on Factory's Droids](https://siliconangle.com/2025/09/25/factory-unleashes-droids-software-agents-50m-fresh-funding/)
- [Port](https://www.port.io)
- [Anthropic skills repository](https://github.com/anthropics/skills)
