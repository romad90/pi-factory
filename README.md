# Agentic factory

A contract-first agentic SDLC on Pi, orchestrated with pi-subagents, on mattpocock/skills v1.3.1, with gates enforced by GitLab CI. Target: **Step 2 (Parallel) on Boris Cherny's ladder, from a laptop.**

**Why it's built this way:** `docs/adr/ADR-001-agentic-factory.md`. Every rule traces to a numbered decision (D1–D37). The path to Step 2 is §11.

## How a mission runs

```
you, main session   /grill-with-docs → /to-spec
/factory <feature>  contract → (you approve) → (you write tickets) →
                    parallel workers → integrate (lint+tests) → fresh reviewers →
                    validator → metrics → (you: /pr, /retro)
```

`/factory` is a loop: `next.sh` says where the mission is, `workflow.sh` generates the exact subagent workflow for the next wave, and the lead passes it verbatim. Subagents get **generated briefs** (file paths, a commit, an id), never the lead's words. Every role runs **fresh**, on **its own model**; judges on **another model family** than what they judge.

## Layout

```
.pi/
  agents/factory/          role agents: contract-author, contract-critic, worker,
                           worker-heavy, reviewer, review-axis, validator
  prompts/                 /factory, /factory-light (lead playbooks)
  settings.json            models per role + fallbacks, model scope, builtins off
  skills/                  mattpocock/skills v1.3.1 (pinned) + contract,
                           contract-critic, verify-behavior
.factory/
  briefs/                  brief templates per role
  skills-pin/              UPSTREAM.md, upstream.txt, skills.sha256, LICENSE
  model-families.json      model id → family, judge/judged rules
  commands.env             lint and test commands for integration
  behavior-paths           paths that force the full lane
instrument/scenarios/      behavior cases: validator only, hidden from workers
scripts/factory/
  next.sh                  mission state + STEP code
  workflow.sh              generates each wave's workflowScript
  brief.sh                 generates a role's brief
  integrate.sh             applies a worker patch, lint + tests, commits
  checkpoint.sh            commits mission state before a wave
  coverage.sh  gate.sh     G2; G1–G4, lanes, briefs, instrument rule
  metrics.sh               per-mission evidence for the MR
  skills-pin.sh            verify / check-global / update the v1.3.1 pin
  models-lint.mjs          one model per role; families separated, fallbacks included
  readiness.sh  doctor.sh  repo readiness; laptop health
  worktree-hook.mjs        hides instrument/ in worker worktrees, sets a port
  install-pi-config.sh     one-time: wires pi-subagents' user config to the hook
docs/adr/  docs/agents/    ADR-001; contract, verdict, checklist, harness formats
.gitlab-ci.yml             factory-config, factory-gate, readiness, behavior replay
AGENTS.factory.md          section to paste into the general AGENTS.md
```

## Setup (S0)

1. `pi install npm:pi-subagents@0.76.1` and remove `@tintinweb/pi-subagents` (one orchestrator only).
2. `scripts/factory/install-pi-config.sh` (once per machine).
3. Fill `.pi/settings.json` (`agentOverrides` models + fallbacks, `modelScope.allow`) and `.factory/commands.env`. Add your models to `.factory/model-families.json` if missing.
4. Paste `AGENTS.factory.md` into AGENTS.md; run `/setup-matt-pocock-skills` (local markdown tracker in `.scratch/`).
5. Merge the factory jobs into `.gitlab-ci.yml`; enable **Settings → Merge requests → "Pipelines must succeed"**.
6. `scripts/factory/doctor.sh` until green; then in Pi: `/subagents-doctor`, `/subagents-models`, and ask to list subagents (only `factory-*`).
7. Dry-run `/factory` on a toy mission with one ticket (ADR §11 lists what to check).

## Day to day

```bash
/factory <feature>                        # in Pi: runs the mission until a human step
scripts/factory/next.sh <feature>         # where is it?
scripts/factory/gate.sh mission <feature> # before pushing
/factory-light <slug> <base>              # code change outside a mission
```

## Lanes

| MR touches | Lane | Needs |
|---|---|---|
| Docs, `.scratch/`, new instrument cases | none | nothing (changed/removed cases need an amendment) |
| Code, no behavior path | light | fresh verdict in `.scratch/light/<slug>/` with a generated brief id |
| A behavior path | full | a mission, G1–G4 |

## On the laptop

- herdr for visibility: one workspace per mission; FleetView or `/subagents-fleet` for the children.
- Keep the machine awake during a mission: `caffeinate -dimsu` (macOS) or `systemd-inhibit --what=idle:sleep bash` (Linux).
- 4 children at a time by default (`parallel.concurrency`, `FACTORY_MAX_PARALLEL`).

## Requirements

Pi with pi-subagents 0.76.1, `bash` 4+, `git` with sparse-checkout (tested with 2.43), `node` (bundled with Pi), `awk`, `grep`, `sed`. Scripts are shellcheck-clean.
