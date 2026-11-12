# P31. Dependency bumps without hands: a scripted install step, outside the agents

**Status:** draft: a guard decision for Rode (see the [November assessment](assessment-2026-11.md)) · **Effort:** M · **Depends on:** D124 (dependency lane), D65; first use is P19 row 1 (dependency and vulnerability bumps)

## Problem

Workers never install (D65, D124). The command guard refuses `npm install`, `npm ci`, `pip install` and the like from a worker (`guard-rules.mjs`, the "network" rules), and the patch guard keeps workers off manifests and lockfiles. That keeps agents off the network and out of the supply chain, and it should stay.

The cost: every dependency change needs the person's hands. In deps-node-22 and eslint-10 the person ran the install, committed it, and recorded it with `/factory-deps`. Dependabot opened 6 PRs on the gym; 2 are still open (get-port 5 to 7, actions/checkout 3 to 7), and `npm audit` reports 28 moderate advisories, all in development dependencies. A loop for them (find, fix, verify the fix, verify behavior unchanged, review, merge: the talk's vulnerability remediation process, P19 row 1) can't run without a person at each install.

## Design

The install is done by a factory script, never by an agent:

1. **Input.** Exact package names and versions, from the request: a dependabot PR's manifest diff, an audit's fix version, or the spec's `## Dependencies` section. The script refuses ranges it didn't get, packages not named, and install scripts (`--ignore-scripts`) unless the project's config lists the package.
2. **Where.** In the mission's worktree, with network allowed to the project's registry only (the proxy's allowlist, or `npm config get registry`).
3. **What it runs.** `npm install <name>@<version> --ignore-scripts`, then `npm ci` on a clean copy to prove the lockfile, then `npm audit --json`.
4. **What it records.** One commit (manifest and lockfile only), logged as kind `deps` in `decisions.tsv` with author "factory install" and the input it came from. `/factory-deps` then works as today (D124): reviewers count those files as delivered.
5. **When.** At a new step after tickets are approved and before the build: `STEP: install`. A person can still do it by hand instead.

## Why it is safe enough

- An agent never chooses what to install: the list comes from the request, and the script refuses anything else.
- No install script runs unless listed.
- The lockfile is proven by `npm ci` on a clean copy, and the audit runs before the build.
- The person still approves the tickets that name the versions (G2), and the MR.

## Steps

1. `install.sh <mission>` for npm, with a stub registry in `tests/factory.test.sh`: named packages install, an unnamed one is refused, an install script is skipped.
2. `STEP: install` in `next.sh` when the spec has a `## Dependencies` section and no `deps` row exists yet.
3. A first loop (P19 row 1) on the gym's dependabot PRs: one mission per PR, started by hand.

## Outside check

- eslint-10 replayed with the step: 0 hand commits for dependencies (it had 1), and `npm ci` on a clean copy passes.
- The next dependabot PRs: each one either merged or closed with a reason, with 0 hand installs.

## Open questions for Rode

- Allow the factory's own script on the network for installs, yes or no? This is the guard decision.
- npm only first, or also pip and others?
- Who may approve an install script exception: the spec, or only `.factory/` config?

## Not doing

No agent gets install rights. No automatic merge: the person merges, as today, until P22's tiers say otherwise.
