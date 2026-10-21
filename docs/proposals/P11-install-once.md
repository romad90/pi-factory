# P11. Install the factory once per machine; onboard a project with only what is its own

**Status:** draft · **Effort:** M · **Depends on:** nothing to start; P2 and P10 fit on top

## Problem

Today `install-into.sh` copies the whole factory into every target repo: about 80 files (scripts, briefs, agents, prompts, the guard, skills, docs). Mission 2 and the first day of mission 3 showed what that costs:

| What happened | Why |
|---|---|
| Each factory release is a 20-to-30-file diff in every project, committed and reviewed by the project's team | The factory's code lives in the project |
| A `git pull` on the cloud machine brought the Mac's models (`kimi-k3`, `glm-5.3`) that its gateway doesn't serve | Models are in agent files committed to the project |
| The factory was installed at a monorepo root instead of its project folder, and had to be cleaned by hand | Installing means writing many files into a target path |
| Two machines ran two factory versions on the same branch (rc.12 and rc.13) | The version is whatever was last copied into the branch |
| Project reviewers see factory scripts, briefs and ADRs in their merge requests | Same |

A project should carry what is about **it**: its commands, its baselines, its behavior paths, its quality bar, its missions. Everything else is the factory, and the factory belongs to the machine.

## Proposal

### Split by owner

| Belongs to | What | Where |
|---|---|---|
| **The machine** (installed once, upgraded once) | scripts, briefs, the 9 agents, the `/factory*` prompts, the command guard, pinned skills, docs | a Pi package: `pi install npm:pi-factory@<version>` (or `git:`/a local path where npm is blocked) |
| **The machine** (its own settings) | models and thinking per role, gateway providers, the probe stamp | `~/.pi-factory/models.json` and `~/.pi/agent/settings.json` `subagents.agentOverrides` |
| **The project** (committed, small) | `.factory/commands.env`, `lint-baseline.txt`, `health-baseline.json`, `behavior-paths`, `model-families.json` additions, `docs/agents/quality-bar.md`, `GLOSSARY.md`, an `AGENTS.md` section, the CI include, and `.factory/VERSION`: the factory version the project expects | the project |
| **The missions** (committed) | `.scratch/<mission>/`, `instrument/` | the project |

### How each piece gets there

- **One package.** pi-factory ships as a Pi package (like pi-subagents): its manifest lists `extensions` (the guard, later the cockpit and the scripted lead), `prompts`, `skills`, and `pi.subagents.agents` (the factory agents load at package scope). The scripts run as `factory <command>` from the package (`factory next`, `factory integrate`, `factory self-check`); briefs name those commands, not `scripts/factory/…` paths.
- **Models per machine.** The package's agents carry no model. Each machine sets them as user-level `agentOverrides` from its profile; `models-lint` and the probe read the effective model. A `git pull` can no longer change which model a machine uses. (To verify on 0.76.1: older pi-subagents refused `factory-*` names in `agentOverrides`; its current docs say package agents receive overrides.)
- **The guard everywhere, active only in a project.** It is already scoped to the nearest `.factory/` folder; installed globally it does nothing elsewhere.
- **Version check.** The pre-flight compares the installed package with `.factory/VERSION`: older than the project expects → stop with the upgrade command; newer → say so, and run (a project can pin with `pi install npm:pi-factory@<version>`).
- **CI.** The MR gate runs the same pinned package: `npx pi-factory@$(cat .factory/VERSION) gate mr`. No factory code in the repo.

### Onboarding a project

One command from inside the project, on its own branch and merge request:

```
/factory-onboard
```

It detects the project folder (a monorepo folder, never the root), proposes the test and lint commands from the project's own files, writes the small set above, runs the baselines, and stops for the human to read the diff: about 8 files, all the project's own.

### Upgrading

```
pi install npm:pi-factory@<new version>     # once per machine
/factory-upgrade                             # per project: bumps .factory/VERSION, migrates its own files if a release needs it
```

A release that changes only the factory changes nothing in the projects.

## What it borrows

- Pi packages and pi-subagents' package agents: the factory installs like the tools it runs on.
- Machinist and Symphony: one runtime on the machine, many repos as work sources.
- zazencodes: what is the project's (`AGENTS.md`, commands, checks) stays in the project; the factory reads it.

## Trade-offs

| For | Against |
|---|---|
| A factory release touches no project; project MRs show project changes only | A project no longer contains everything needed to run its missions; the package version is the contract (`.factory/VERSION`, checked at pre-flight and in CI) |
| Models per machine, never pulled from another machine | Depends on pi-subagents applying `agentOverrides` to package agents; to verify on the pinned version before anything else |
| Onboarding is one command, about 8 files | Migration of the projects already installed (bridge): a one-time `/factory-upgrade` that removes the copied factory files |
| The cockpit (P10) and the scripted lead (P2) ship as extensions of the same package | Air-gapped or blocked-npm machines need a local or git install path; kept as an option |

## Plan

1. Spike: package agents plus user `agentOverrides` on pi-subagents 0.76.1 (else the version that supports them). **S**
2. Package manifest; `factory` command wrapping `scripts/factory/*`; briefs and prompts use it. **M**
3. Models from the profile as user overrides; lint and probe read effective models. **S**
4. Version check at pre-flight; CI through the pinned package. **S**
5. `/factory-onboard` and `/factory-upgrade` (with the migration that removes copied files). **M**
6. Migrate bridge after mission 3. **S**

## Open questions

- npm, git or a local tarball as the default source behind the corporate proxy? Proposed: npm where reachable (pi-subagents already installs that way), a local path otherwise.
- Keep `docs/factory/*` in projects for readers who never open the package? Proposed: no; the `AGENTS.md` section links to the installed docs and to the repository.
