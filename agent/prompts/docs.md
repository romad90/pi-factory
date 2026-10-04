---
description: Documentation pass on a legacy module, or diff-driven doc catch-up on a branch
---
Documentation pass for: $@

1. If the argument is a branch or an issue: run `documentalist` in DIFF mode on it.
2. If it is a module or folder path: create a worktree (git worktree add ../wt-docs-<slug> -b docs/<slug>) and run `documentalist` in LEGACY mode on it.
3. Run `reviewer` on the result with this instruction: check every documented statement against the code; flag anything false or presented as fact while inferred.
4. Show me CONTRADICTIONS FOUND and TO CONFIRM BY HUMAN. These are decisions for me, not for agents.
5. `mr-writer`, then log one line to .factory/runs.jsonl (schema in ~/.agents/AGENTS.md) with "type":"docs".

At start, set the issue's Status to in-progress. At the end, set it to done (ready for MR) or blocked.
