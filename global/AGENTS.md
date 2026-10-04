# Global rules (all projects, all agents)

Layers, most general first: this file → kit AGENTS.md (bot, api, front) → project AGENTS.md.
More specific layers override on project facts (commands, conventions, structure).
Nothing overrides the hard rules below.

## Hard rules
- Never push, force-push, rebase shared branches, merge, or open merge requests. Humans do that.
- Never read, print or write secrets, tokens, `.env` files or production configuration.
- Never run anything against production, shared environments, real accounts or real channels.
- Never delete files outside your worktree. No `rm -rf` outside build artifacts.
- Never disable, skip or weaken tests or lint rules to make a check pass.
- Never add a dependency without stating it in your final report.
- Ambiguity or a design decision → stop and ask. Do not guess.
- Same error after 3 genuine attempts → stop and report BLOCKED.

## Factory conventions
- Issues: `issues/NNN-slug.md` from `issues/TEMPLATE.md`. Scope decisions: `issues/decisions/`. PRDs: `issues/prd-*.md`.
- ADRs: `docs/adr/`, drafts in `docs/adr/drafts/`. Domain vocabulary: `docs/CONTEXT.md`.
- Worktrees: `../wt-<slug>`, one per issue. Agents work only inside theirs.
- Factory output: `.factory/runs.jsonl`, `.factory/mr/`, `.factory/handoffs/`.
- Skills: `~/.agents/skills/` (project `.agents/skills/` overrides).

## Run log
Every pipeline appends one JSON line to `.factory/runs.jsonl`:
`{"date","type","issue","worker_model","model_actual","fallback","status","review_a","review_b","agreement","drift","fix_rounds","human_needed","duration_min"}`
`model_actual` is the model that really ran. Use null for fields that do not apply.

## Reporting
- End every task with the result block your role defines. Facts only; say "unknown" rather than guess.
