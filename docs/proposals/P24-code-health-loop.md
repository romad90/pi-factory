# P24. Code health as a closed loop, for any language

Status: queued (after the current job; no factory change during a mission).

Source: Adam Tornhill, "AI-Friendly Code" (GOTO Copenhagen 2026). Agents told only to "improve" fix 20–50% of health issues; given a measured gap they close most of it (closed-loop control). A refactoring playbook the agent writes as it goes, specific to the codebase, made large refactors mechanical. Change coupling and author density find the modules every change collides in. The speaker sells a proprietary metric: we take the method, not the score.

## What we build, language-agnostic

1. Function-level measures with Lizard (one tool, about 20 languages): length, cyclomatic complexity, parameter count per function. `health.sh` keeps its indentation-based measures. No Lizard installed: a warning, not a failure.
2. A ratchet per file, per ticket: when a ticket ends, each file it touched is compared with its value before. A worse value goes back to the worker as a fix round, before the judges.
3. Change coupling in `measure.sh`, from `git log` alone: shared commits ÷ average revisions (code-maat's formula). The architect gets coupled pairs and god modules as measurements; the ticket writer keeps parallel tickets off the same file.
4. `docs/agents/refactoring-playbook.md` per project: a passing refactor ticket adds its recipe (when it applies, constraints, mechanism); the code steward checks it against the diff; refactor briefs include it.
5. `FACTORY_LINT_CMD` stays each project's own linter (ruff, golangci-lint, eslint…): the factory does not choose it.

## How we know it works

- Fixture repos in TypeScript, Python, Go, Java and C, each with a planted unhealthy function: the ratchet catches each one and passes the clean versions.
- On past missions: files the sensor flags have more fix rounds or escaped defects than files it doesn't. If not, it ships as a warning only.
- One real refactor mission adds at least one recipe the steward confirms.

Not taken: a single 1–10 score, a parser per language (tree-sitter), the vendor's MCP server.
