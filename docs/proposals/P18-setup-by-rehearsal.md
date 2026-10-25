# P18. Setup by rehearsal: the factory finds its own commands and proves them as a worker would

**Status:** draft · **Effort:** M · **Depends on:** P11 (onboard); none of the mission loop changes

## Problem

Onboarding the first project on the installed package (mission 4, a TypeScript worker with no active tests) took an evening of screenshots and back-and-forth. Every step was a person reading output and guessing the next command. What was found by hand, in order:

| Found by hand | What would have happened in the mission |
|---|---|
| The models profile was an old capture: 9 agents of 12, and old model ids | Design and investigation steps fail on a placeholder |
| Floating model aliases (`*-latest`) | The probe stamps an alias; a silent model change breaks comparisons |
| The judges' route goes to a production gateway | Every review round spends the shared production quota |
| `NODE_TLS_REJECT_UNAUTHORIZED=0` in the environment | Gateway calls, key included, with certificate checks off |
| The factory sits in a subfolder of an internal mirror | `package-sha` records the mirror's commit; CI can't link it |
| `npm ci` runs `npm audit fix` as a lifecycle script | Dependencies and the lock change behind the mission's back |
| `jest` is configured but not installed: `npx jest` downloads it | A worker, offline, can't run the tests at all; versions float |
| No tests: plain `jest` exits red | Every round fails on "base already red" |
| The skills pin compares absolute and relative paths | `doctor` reports tampering that isn't there |
| The deploy-on-push branch pattern and the forge's push rules | The MR push deploys a branch, or is refused at the end |

Each of these is a fact about the machine or the repo that a script can read or test. None needed a person, except to decide what to do about it.

## Proposal

`factory setup` (run by `factory onboard`, and on its own later): discover, rehearse, report. Deterministic first; a model only where the repo's own text has to be read.

### 1. Discover, from the repo's own sources of truth

In this order, because the first ones are the ones the team already trusts:

1. **The project's CI file** (`.gitlab-ci.yml` and what it includes): the install, test and lint jobs are the commands the team already runs. A short read by an efficient model turns the job scripts into candidates, each with the line it came from.
2. **Manifests**, one table per ecosystem: `package.json` (scripts, devDependencies, the lock's package manager), `pyproject.toml`/`pytest.ini`, `go.mod`, `Cargo.toml`, `pom.xml`/`build.gradle`, `Makefile`. A runner declared in config but absent from the dependencies is a finding (`jest.config.js` without `jest`).
3. **Lifecycle scripts** that run on install (`preinstall`, `install`, `postinstall`, `prepare`): listed, and flagged when they write (`audit fix`, code generation, `git`).

Output: candidates for `FACTORY_TEST_CMD`, `FACTORY_TEST_FILES_CMD`, `FACTORY_LINT_CMD`, `FACTORY_DEPS_CMD`, each with its source.

### 2. Rehearse, as a worker would

A candidate is kept only if it works **under a worker's conditions**, the ones D100 imposes:

- in a fresh worktree of the base commit, dependencies linked the way the worktree hook links them;
- network off, credential variables scrubbed, the command guard on;
- run twice: green, and the same result both times (a flaky base is a finding).

Then three properties, each a check:

| Check | Fails when |
|---|---|
| Local tools only | The command downloads (`npx` fetching a package, a pip install) |
| Install leaves the tree clean | `git status` shows `package.json`, a lock or tracked files changed after the install |
| Green base, failing test is red | A planted failing test file doesn't turn the run red (the command ignores tests) |

The lint candidate runs once to write the baseline (D62).

### 3. Reflect: the environment, the same way

The machine and the gateway get the same treatment, as `doctor` checks with the reason and the fix:

- every factory agent has a model; none is a floating alias (`latest`, no version);
- each model's route is classified by a pattern you set once (`FACTORY_GATEWAY_PROD_RE`): judges or workers on a production route are a warning, with the role and the quota it spends;
- TLS checks are on (`NODE_TLS_REJECT_UNAUTHORIZED` unset; `NODE_EXTRA_CA_CERTS` suggested for an internal authority);
- the factory's checkout layout (own repo or subfolder of a mirror) recorded next to `package-sha`, so CI links the right folder;
- the forge: does pushing a branch deploy (from the CI rules), and does a push rule reject the factory's commit author.

### 4. Report, and the human approves

`setup.md` in `.factory/`: what was found, from where, what was rehearsed, the result, and what needs a decision ("jest is configured but not installed: add `jest`, `ts-jest` and `@types/jest` as devDependencies, versions from the lock of a sibling repo or the latest compatible; this changes package.json, test tooling only"). The commands go into `commands.env` only for what passed rehearsal; the rest stays commented with the reason. The human reads one page and decides, instead of discovering each item at a red prompt.

## What it does not do

- It installs nothing and changes no dependency: missing tooling is a decision, written as one.
- It does not fix vulnerabilities it sees in the install output; they go in the report as a finding for the team.
- It does not replace the human's approval of the commands: rehearsal shows they work, not that they test the right thing.

## Trade-offs

| For | Against |
|---|---|
| Any language: the CI file and the rehearsal don't care which | A table per ecosystem to keep, and a CI file can be too indirect to read (templates from another repo) |
| Problems found before the first round, with their fix, not mid-mission | Rehearsal costs a few minutes and one or two full test runs |
| The worker's conditions are tested once, at setup, not discovered by a failed round | A test suite that needs a service can't pass offline: that is a finding, not a failure of setup |
| The same checks re-run after any upgrade or model change | |

## Plan

1. Fix the two bugs found: skills pin paths in package mode; `package-sha` with the factory in a subfolder (record the folder, CI links from it). **S**
2. `doctor` environment checks: placeholders named per agent, floating aliases, production routes, TLS off. **S**
3. Discovery: CI file read, manifest tables (Node, Python, Go, Rust, JVM), lifecycle scripts. **M**
4. Rehearsal in a worker worktree: offline, scrubbed, guard on, twice; the three checks. **M**
5. `setup.md` report and `commands.env` writing; `factory onboard` runs it. **S**

## Open questions

- Should rehearsal also run a planted characterization test, to prove `FACTORY_TEST_FILES_CMD` really narrows to the given files? Proposed: yes, it is one more run.
- The CI file read by a model: keep it, or parse the common shapes (`script:` lines of jobs named test, lint) and fall back to the model only when nothing matches? Proposed: parse first.

## What it borrows

- Google's Elephant-Goldfish Model: its bootstrap skill starts with "ecosystem and verification discovery" from the manifests.
- Our own worker conditions (D65, D100): setup tests the commands where they will run, not where the human runs them.
