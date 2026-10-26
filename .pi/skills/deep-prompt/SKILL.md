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

Ask one question: go with the deeper version, edit it, or keep the original. Then the human starts `/grill-with-docs` with `depth.md` named as its first input, so the grilling asks only what it leaves open. This skill never starts the work.
