---
name: deep-prompt
description: The factory's depth step before a spec. Applies the deepen-prompt method (what a top practitioner would add, the rawest material, the methods and tools, an outside check) to a mission's task and writes .scratch/<mission>/depth.md, whose outside checks become candidate contract assertions. Use before /grill-with-docs, or when the human says deep-prompt or genius-mode.
---

# Deep prompt (factory)

The method is the `deepen-prompt` skill, vendored unchanged in `.pi/skills/deepen-prompt/` (MIT, from r3dlex/deepen-prompt, after Felix Rieseberg's depth prompt). Read its `SKILL.md` and follow it: identify the field and the unchanged goal, answer its four questions, rewrite the prompt, and respect its anti-patterns (deeper, not bigger; methods, not persona; no self-grading). Its `references/domains.md` and `references/examples.md` are starting points.

This skill only adds what the factory needs from it (D104).

## Size it first

A fix-lane change, a rename or a one-line correction: say in one line that it doesn't need depth, and stop.

## Raw material in a factory mission

Look here before anything digested (an audit report, a retro, a ticket's summary): the code and its git history (`git log -p` on the paths involved), the tests that exist and the ones that don't, the CI file, real payloads or fixtures, run logs, and, for an existing mission, its run archive (`factory archive list <mission>`). Name what exists in this repo and how to reach it; name what is missing and the access it needs.

Also read, every time:
- `scripts/factory/health.sh details`: where the duplicated blocks, large files and deep nesting are (`dup <file:line> = <file:line>`). Duplicated logic is where a later refactor merges copies; the differences between copies are what a characterization mission must pin, each copy separately.
- Who uses the code: imports of this package or module elsewhere in the repository (`git grep`), to rank entry points by real use before churn.

## Rules the depth must respect

Each one comes from a human correction of a depth file (D104). A rule here replaces that correction next time.

- **Who runs each check.** A worker can't touch the mission's frozen paths (`src/` in a maintenance mission, `## Frozen paths` otherwise): the patch guard refuses it. A check that needs them changed (a mutation, a deliberate break) is run by a person or a tool after the mission, never written into tickets. Mutation testing means one Stryker (or the language's tool) run by a person on the pinned modules after the mission, its score recorded as data; not a single hand-picked mutation.
- **Coverage proves reach, not pinning.** Every spec asserts an output, a thrown error or a side effect. A check on coverage alone passes a spec that asserts nothing.
- **Determinism.** Anything touching time, dates, formatting, randomness, logs or the environment fixes it in the spec (a fake clock and a fixed date, a fixed `TZ` and locale, a seeded random, captured output). A spec that passes on one machine and fails in CI is worse than none.
- **The project's commands.** Checks name `FACTORY_TEST_CMD`, `FACTORY_TEST_FILES_CMD` and `FACTORY_LINT_CMD` from `.factory/commands.env` (rehearsed by `factory setup`, D102), never `npx …`: workers run offline.
- **Where tests go.** New tests follow the runner's config (jest `testMatch`, pytest's `testpaths`, …) and the project's naming (`.spec` or `.test`); say which in the depth.
- **Size.** At most 12 stories, ordered by real use, then by churn. Anything beyond goes under "Not doing" as a next mission.

## Write depth.md

Write `.scratch/<mission>/depth.md` (show it instead when there is no mission folder yet), in deepen-prompt's output template, plus two factory sections:

```markdown
## Outside checks (candidate assertions)
- <check> — passes when <observable condition>, run by <test, tool or person>
## Not doing
- <the "bigger" temptations cut, and why>
```

Write each outside check so the contract author can turn it into an assertion with an ID. At least one must be a check a tool runs (a test, a mutation score, a benchmark), not a model's opinion.

## Then stop

Ask one question: go with the deeper version, edit it, or keep the original. When the human edits it, apply the edits to `depth.md` and list each one at its end under `## Human edits`, one line each: that list is what the next version of these rules is made from. Then the human starts `/grill-with-docs` with `depth.md` named as its first input, so the grilling asks only what it leaves open. This skill never starts the work.
