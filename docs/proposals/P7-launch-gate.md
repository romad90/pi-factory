# P7. Launch gate: a mission is done when the service runs, in a sandbox, secure by design

**Status:** draft · **Effort:** M · **Depends on:** nothing to start; the sandbox levels of [agent-sandboxing](../research/agent-sandboxing.md)

## Problem

A mission ends today when tests and review pass. That proves the code is correct in isolation, not that the service runs.

Mission 1 (a bot) went to staging after the factory said done, and needed several fixes by hand: framework configuration (module wiring at start-up) and environment variables the service needs to boot. None of it was visible to unit tests, all of it was visible the moment the service started.

A second problem sits under the first: every tool in the chain (agent runtime, dependencies, containers, model gateway) is accepted with some security debt. Running the real service to check it adds more risk unless the check itself is designed to be safe.

## Proposal

### 1. G6, the launch gate

`next.sh` reaches `pr` only after G6 passes. Three levels, each a command in `commands.env`, each optional so a team can start with the first:

| Level | Command | Proves |
|---|---|---|
| Build | `FACTORY_BUILD_CMD` (e.g. the CI image build) | The artifact the pipeline will ship builds from the mission branch |
| Boot | `FACTORY_LAUNCH_CMD` + `FACTORY_READY_CHECK` | The service starts with the target environment's configuration and reaches ready: process alive, health endpoint or first log line, a dry run for a batch or bot |
| Smoke | `FACTORY_SMOKE_CMD` | After a human deploys to staging, a short check of the real endpoints; the factory writes it, runs it, records the result |

**Configuration is checked, not guessed.** The repo declares the environment it needs: a schema of variables (name, required, format, secret or not), `.env.example` generated from it. G6 fails on a missing or malformed variable with its name, before booting. The same schema validates staging's configuration, so "works locally, not in staging" becomes a named difference.

**Every fix made by hand after a mission becomes a check.** The retro lists them; each one turns into a line of the schema or of the ready check. Mission 1's fixes are the first ones.

### 2. The launch runs in a sandbox, secure by design

The service starts in a disposable, isolated environment, never on the host:

- **Container or micro-VM per launch**, built from the repo's own image, root filesystem read-only, a writable scratch folder only.
- **No network except an allowlist** declared per repo (the mocked dependencies, a local database container). No route to production, ever: the sandbox has no production credentials and no production network.
- **Secrets never visible to agents.** The sandbox gets placeholders; a host-side proxy substitutes real values only for the allowed hosts (level 2 of the sandboxing study). For a local boot, test credentials only.
- **Dependencies from the team's registry or mirror**, with the lock file enforced; install scripts run inside the sandbox, so a malicious `postinstall` stays contained.
- **Destroyed after the gate.** Nothing persists but the log and the result in the mission folder.

Same rules for every agent command later (the study's levels 1 to 3): G6 is where the factory starts running code it wrote, so it is where the sandbox starts.

### 3. Secure by design, as factory rules

Security debt can't be removed, but it can be named and kept from growing:

- **Least privilege by default:** each role gets only the tools, paths and network it needs; the lead can't write code, workers can't push, nothing can deploy.
- **A debt register:** every accepted risk (a dependency, a tool without a sandbox, a secret in a file) is a line in `docs/factory/security-debt.md` with owner and review date. The steward reports new entries; the ratchet says the list can only shrink without a decision.
- **Deterministic security checks in the gates:** dependency audit and an offline static scan on the patch (from [ideas to borrow](ideas.md)), secret scanning on every patch, image scan for G6's build.
- **No vendor holds state or credentials:** the sandbox and its proxy run on the team's machines.

## Trade-offs

| For | Against |
|---|---|
| "Done" means "it runs": staging stops being where the factory's bugs are found | Building and booting adds minutes per mission. Run G6 once per mission, not per ticket |
| Configuration errors become named, testable failures | Someone writes the environment schema once per repo. The first mission can draft it from the code and the staging config |
| A launch can't touch production or leak a secret by construction | Containers or micro-VMs need tools IT may have to approve; the study's level 1 (OS sandbox) is the fallback |
| Security debt becomes visible and owned | A register no one reads is noise. The steward reports changes to it in every MR |

**Rejected alternative:** let the agent deploy to staging and check there. It needs deployment rights and puts agents one permission away from production.

## What it unlocks

- **A mission that ends with a running service**, the statement that the goal is reached.
- **P6's incident lane** can reproduce an incident by booting the service with the incident's configuration.
- **The sandbox for every agent command**, started where the risk is highest.

## Plan

1. `FACTORY_BUILD_CMD`, `FACTORY_LAUNCH_CMD`, `FACTORY_READY_CHECK`, `FACTORY_SMOKE_CMD` in `commands.env`; G6 in `next.sh` before `pr`. **S**
2. Environment schema and its check, `.env.example` generated. **S**
3. Launch inside a container with read-only root, no network but the allowlist, test credentials. **M**
4. Secret scanning and dependency audit on every patch; image scan in G6. **S**
5. Security debt register and the steward's report. **S**
6. Move to micro-VMs with host-side secret injection (study level 2) when IT allows. **M**

## Open questions

- Which container runtime is allowed on the team's laptops and CI runners?
- Does the team already have an environment schema convention per framework that G6 should read instead of a new file?
