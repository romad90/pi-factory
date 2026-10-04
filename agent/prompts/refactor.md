---
description: Run one refactor issue — characterize, refactor in small steps, drift check, review, MR text
---
Run the refactor pipeline for issue: $1

1. Read the issue. Stop unless it states the target structure, the area, and what must not change.
2. Worktree: git worktree add ../wt-<slug> -b refactor/<slug>
3. Run `refactorer` with the issue path and worktree path.
4. BLOCKED → stop, show me.
5. DONE → run `drift-checker` FIRST. This is mandatory.
   - DRIFT not allowed by the issue → stop and show me. Do not ask the refactorer to "fix" it without me.
   - UNCERTAIN → stop and show me.
   - NO_DRIFT → continue.
6. Run `reviewer` and `reviewer-2` in parallel, asking them to focus on: is the new structure actually better, is the scope respected, were characterization tests left untouched.
7. Same fix-round and arbitration rules as /afk; after any fix round, re-run `drift-checker`.
8. `documentalist` DIFF mode (architecture docs, module boundaries), then `mr-writer`.
9. Log one line to .factory/runs.jsonl (schema in ~/.agents/AGENTS.md) with "type":"refactor" and "drift": <verdict>.
10. Report in 5 lines.

At start, set the issue's Status to in-progress. At the end, set it to done (ready for MR) or blocked.
