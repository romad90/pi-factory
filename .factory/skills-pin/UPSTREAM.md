# Upstream skills pin

**Source:** https://github.com/mattpocock/skills
**Version:** v1.3.1
**Commit:** 24fe0ef7737efae15c87225755e9f6f5965e4888
**Copied on:** 2026-10-07
**License:** MIT (`LICENSE-mattpocock-skills`)

Vendored into `.pi/skills/<name>/`, flattened from upstream's
`skills/<category>/<name>/`. The list is `upstream.txt`; every file is hashed
in `skills.sha256`. CI runs `scripts/factory/skills-pin.sh verify` on every MR:
any edit, swap or missing skill fails it (D36).

## Why `.pi/skills/` and not `.agents/skills/`

- pi-subagents resolves project skills from `.pi/skills/` first, and doesn't
  list `.agents/skills/` among its subagent skill locations.
- pi-subagents also scans legacy `.agents/**/*.md` for agent definitions, so
  skills under `.agents/` would be registered as agents.
- Each factory agent adds `skillPath: ../../skills`; local matches win over any
  machine-wide copy, so subagents always get the pinned version.

## Vendored (18)

| Skill | Role in the factory |
|---|---|
| grilling, grill-with-docs, grill-me | Clarifier (human, main session) |
| domain-modeling, codebase-design | Dependencies of grill-with-docs, tdd, code-review |
| to-spec, to-tickets, setup-matt-pocock-skills | Spec and tickets (human, main session); tracker setup |
| tdd | factory-worker |
| code-review | factory-reviewer (dispatches both axes to factory-review-axis) |
| diagnosing-bugs | Bug missions |
| pr, retro | Close-out |
| improve-codebase-architecture | Periodic, outside missions |
| writing-for-agents | Editing skills, agents, AGENTS.md; used by retro |
| handoff, teach | Only when work must travel (handoff), learning (teach) |
| setup-pre-commit | Readiness: pre-commit hooks |

Not vendored: `implement`, `implement-spec` (orchestration is ours, D33),
`wayfinder`, `wizard`, `triage`, `research`, `prototype`, in-progress and misc skills.

## Local skills (ours, not in the manifest)

`contract`, `contract-critic`, `verify-behavior`.

## Upgrade procedure

1. Read upstream's CHANGELOG from v1.3.1 to the target.
2. Note breaking changes (renames, removed skills, file conventions).
3. Replace the folders listed in `upstream.txt`; local skills are untouched.
4. `scripts/factory/skills-pin.sh update`, update this file and `required_version` in `skills-pin.sh`.
5. Run one light-lane change and one mission end to end before merging.
