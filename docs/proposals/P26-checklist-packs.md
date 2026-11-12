# P26. Checklist packs: what a good contract looks like for a kind of change, asked in round 1

**Status:** draft, for review before the nightly loop builds it · **Effort:** S · **Depends on:** nothing new (the slot exists)

## Problem

The contract author and the critic already read `docs/agents/contract-checklist-<domain>.md` (`.pi/skills/contract/SKILL.md`, line 10; `.pi/skills/contract-critic/SKILL.md`, line 10; both briefs say "every docs/agents/contract-checklist-*.md present"). No pack exists, in the factory or in any project. The eslint-10 critiques each say there are no domain checklist packs.

eslint-10 shows the cost. The change was a lint configuration, and the critic found its weak spots one at a time:

| Round | Blocking finding | The person's amendment |
|---|---|---|
| 1 | `no-shadow` checked on 4 files only; extra `no-unused-vars` options allowed | check all 58 files; pin the options |
| 2 | `no-shadow` options not pinned (`allow: ['client']`) | pin the full value |
| 3 | every file compared with `lib/server.js`, itself not independent (`comma-style` relaxed globally) | compare with plain neostandard |
| 4 | the author could not place the reference config (a decision) | `.scratch/<mission>/tmp/` |
| 5 | globals and ignore patterns not limited | pin the file's exact shape |

Five amendments and one decision: 6 of the mission's 11 human decisions. Every round was a real finding. Each would have been one line of a checklist the author read before round 1.

## What it is

A pack is a short list of yes/no questions for one kind of change. The author answers each one in the contract (an assertion, or a line in "Not covered" saying why not). The critic checks that each one was answered. A pack holds questions, never project facts.

This is the "skill = what good looks like" idea from the trusted-factory talk (Tessl, AI DevCon, November 2026): define good once for a kind of work, and reuse it at every run.

## Design

1. Packs ship with the factory under `docs/agents/contract-checklist-<kind>.md` and are linked into projects like the other `docs/agents` files (`scripts/factory/package-links.txt`). A project may add its own packs next to them.
2. The spec names its kind on one line (`**Kind:** config-upgrade`), or the author picks the packs whose "Applies when" line matches the scope. When no pack applies, the contract says so.
3. The critic's brief gets one rule: a pack question with no answer is a [blocking] finding, with the question as its "Passes wrongly" line.

## The first pack (draft)

`contract-checklist-config-upgrade.md`. Applies when: a tool's configuration or version changes (linter, formatter, test runner, bundler, CI).

1. Is the configuration's exact shape pinned (its entries, in order, and no other key)?
2. Is each file's resolved configuration compared with a reference built from the upstream preset alone, outside the mission's own config?
3. Are the exceptions to that reference listed one by one, with their exact values?
4. Is the set of ignored or excluded paths closed (exactly these, nothing added)?
5. Were the numbers the contract states (file counts, test totals, finding counts) measured on the base commit, with the command and the date?
6. Does every assertion's command exist in the target version (checked with the tool's `--help` or its files under `node_modules`)?
7. Is the "Done when" command available to every reviewer whose assertion names it (D132)?
8. Which files under test folders are tool configuration, not tests (D131)?

Later packs, from the same retros: `dependency-upgrade` (deps-node-22: lockfile, audit by severity and by path, engines, test counts on base); `bugfix` (a reproduction that fails on base).

## Steps

1. Write the pack above, link it, and add the critic's rule. Test: a contract fixture with question 4 unanswered gets a [blocking] critique line in `tests/factory.test.sh` (the brief carries the rule; the parser reads it).
2. Replay: run the contract wave of eslint-10 again from its spec, with the pack, on a copy of the gym (`bench.sh`).

## Outside check

- eslint-10's contract, rewritten with the pack, reaches a critique with no blocking finding in 2 rounds or fewer (it took 6).
- The next config or tool mission needs 2 contract amendments or fewer.

## Open questions for Rode

- Ship packs in the factory, or keep them per project? (Draft: in the factory, since none of the questions above is about ldapjs.)
- Should a missing answer block (critic rule), or only warn at G1?

## Not doing

No pack per language or framework yet. One pack, measured, then the next.
