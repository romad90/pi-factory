---
description: Run several parallel-safe AFK issues at once (max 3), routed by type
---
Run these issues in parallel: $@

1. Read every issue. Refuse to start if any is not AFK, or if two of them touch the same files. Tell me which pair conflicts.
2. Maximum 3 at a time. Take the first 3, list the rest as queued.
3. Route each issue by its Type and follow that pipeline's steps exactly, concurrently:
   feature → /tw23-afk, bug → /tw23-bug, refactor → /tw23-refactor, docs → /tw23-docs, spike → /tw23-spike.
4. Never merge or push anything.
5. Finish with one table: issue — type — status — review A — review B — drift (refactors) — fix rounds — needs me (yes/no).
