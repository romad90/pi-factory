---
description: Run one bug issue — reproduce with a failing test, root-cause fix, review, MR text
---
Run the bug pipeline for issue: $1

1. Read the issue. Stop if it lacks symptoms, expected behaviour, or reproduction hints.
2. Worktree: git worktree add ../wt-<slug> -b fix/<slug>
3. Run `debugger` with the issue path and worktree path.
4. CANNOT_REPRODUCE or BLOCKED → stop and show me what was tried.
5. FIXED → run `reviewer` and `reviewer-2` in parallel. Ask them to also check that the reproduction test fails on the base branch and that the stated root cause matches the fix.
6. Same fix-round and arbitration rules as /afk (max 1 round, then me).
7. If the fix changes documented behaviour → `documentalist` DIFF mode. Then `mr-writer`.
8. Log one line to .factory/runs.jsonl (schema in ~/.agents/AGENTS.md) with "type":"bug" and "same_pattern_elsewhere": <count>.
9. Report in 5 lines. List SAME PATTERN ELSEWHERE as candidate new issues.

At start, set the issue's Status to in-progress. At the end, set it to done (ready for MR) or blocked.
