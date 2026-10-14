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

## What to watch for

Each of these tools keeps something we don't want to give away: the runtime (OpenCode Swarm needs OpenCode), the hosted control plane and its data (Factory, Port), or a maintainer we depend on. The test for anything we take: does it keep working if that vendor disappears tomorrow?

## Sources

- [OpenCode Swarm](https://swarmai.site)
- [Factory](https://factory.com/), [SiliconANGLE on Factory's Droids](https://siliconangle.com/2025/09/25/factory-unleashes-droids-software-agents-50m-fresh-funding/)
- [Port](https://www.port.io)
