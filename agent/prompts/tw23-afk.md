---
description: Run one AFK feature issue end to end — worktree, build, double review, docs, MR text
---
Run the feature pipeline for issue: $1

1. Read the issue. Stop if it is not AFK, has no acceptance criteria or verification command, or its Type is not feature (point me to /tw23-bug, /tw23-refactor, /tw23-docs or /tw23-spike instead).
2. Create the worktree: git worktree add ../wt-<slug> -b agent/<slug>
3. Run `builder` with the issue path and worktree path.
4. BLOCKED → stop, show me the blocker.
5. DONE → run `reviewer` and `reviewer-2` in parallel, independently (neither sees the other's output).
6. Any BLOCKING finding → `builder` once more with only the blocking findings, then both reviewers again. Max 1 fix round. Still blocking or still disagreeing → stop and show me both reviews side by side.
7. Both APPROVE → run `documentalist` in DIFF mode, then `mr-writer`.
8. Log one line to .factory/runs.jsonl (schema in ~/.agents/AGENTS.md), type "feature".
9. Report in 5 lines, with the branch and the MR text path. I open the MR.

At start, set the issue's Status to in-progress. At the end, set it to done (ready for MR) or blocked.
