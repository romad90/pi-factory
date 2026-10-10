# Contributing

This repo is a template: improvements land here, then reach target repos with `scripts/factory/install-into.sh`.

## Branches

| Branch | Role |
|---|---|
| `develop` | default branch; every PR targets it; pushes publish prereleases (`x.y.z-rc.N`) |
| `main` | releases only; updated by merging `develop` |
| `feat/…`, `fix/…`, `docs/…`, `chore/…` | work branches |

## Commits

[Conventional Commits](https://www.conventionalcommits.org), checked on every PR:

- `feat:` a new capability → minor; `fix:` → patch; `feat!:` or a `BREAKING CHANGE:` footer → major.
- `docs:`, `test:`, `chore:`, `ci:`, `refactor:` → no release.
- In the body, say the **issue** (with mission evidence when there is some) and the **fix**. Curated release notes in `docs/releases/` are built from those bodies.

## Working on the factory in Pi

This repo ships the command guard (`.pi/extensions/factory-guard.ts`), which blocks writes to `scripts/factory/`, `.pi/` and `.factory/`, exactly what you change here. Start Pi with `FACTORY_GUARD=off pi` when you work on the factory itself. Never in a target repo: there the guard is what keeps agents from changing their own rules.

## Before a PR

```bash
shellcheck -S warning scripts/factory/*.sh scripts/dev/*.sh tests/*.sh
bash scripts/factory/skills-pin.sh verify
node --test tests/guard.test.mjs
bash tests/factory.test.sh
```

A behavior change in a script needs a check in `tests/factory.test.sh`; a guard rule needs a case in `tests/guard.test.mjs` (both what it blocks and what it must still allow). A new decision needs an entry in the ADR (`docs/adr/ADR-001-agentic-factory.md`) with its *Why*, and a line in the section of `docs/DESIGN.md` it belongs to. A feature isn't done until the cheat sheet says how to use it and the design guide says why it exists.

## Releases

semantic-release runs on pushes to `develop` and `main` (`.github/workflows/release.yml`): it computes the version, tags `v<version>`, updates `CHANGELOG.md` and `.factory/VERSION`, and publishes a GitHub release. After a release on `main`, the same workflow merges `main` back into `develop` (`chore: sync develop with main`), so there is no sync PR to open by hand. Release and sync commits carry no CI skip marker: one of them is often the head of the next `develop` → `main` PR, and a marker there would skip its required checks forever. The release job skips its own commits by subject. If the two branches conflict, the step fails and says so: open a `main` → `develop` PR and resolve it.

It pushes with the `RELEASE_TOKEN` secret (a fine-grained token of a repo admin on the ruleset's bypass list), so it works on protected branches. Write `docs/releases/<version>.md` for releases with user-facing changes.

## Practice packs

A pack is content, never code (ADR D54): `packs/<name>/docs/agents/contract-checklist-<name>.md` and `quality-bar-<name>.md`, with stable `QB-<NAME>-NN` IDs, listed in `packs/README.md` and the README. Items must be checkable as an assertion or on a diff. Short beats complete.

## Licence

MIT. By contributing you agree your contribution is under the same licence.

## After a mission

1. `/retro` in the target repo; findings go to `docs/retros/mission-NN.md` here.
2. Update `docs/LADDER.md` (evidence log and criteria).
3. Open roadmap items as issues: `scripts/dev/open-roadmap-issues.sh`.
