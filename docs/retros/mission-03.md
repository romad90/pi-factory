# Retro: mission 3

Characterization of the licenses feature production added to a batch worker (anonymized). Findings are added while the mission runs. Priority: **P1** blocks or wastes a lot · **P2** friction · **P3** nice to have.

| # | Finding | Evidence | Fix | P | Status |
|---|---|---|---|---|---|
| 1 | A pull brought another machine's models | the cloud machine's agents pointed at models its gateway does not serve; the probe caught it before any wave | models per machine | P1 | P11 |
| 2 | The factory installed at a monorepo root | `install-into.sh` given the repo root; cleaned by hand | onboarding detects the project folder | P2 | P11 |
| 3 | A `## Frozen path` typo would have unfrozen `src/` | the patch guard reads `## Frozen paths` only | the pre-flight refuses a spec without the section | P2 | roadmap |
| 4 | A reviewer asked whether a missing deliverable fails | ticket 14, README changed instead of the docs | brief rule and resolver | P2 | ✅ D82 |
| 5 | A conflicted 3-way apply blocked every integration | four tickets wrote one test file; the tree was left unmerged | restore and record a round; tickets of a wave never share a file | P1 | ✅ D80, D83 |
| 6 | Escalation on a stale verdict | 14 escalated on a review of an older commit; its docs were never reviewed | stale verdicts are not rounds | P1 | ✅ D81 |
| 7 | The team quota ran out with three parallel workers | 429 on two tickets | `FACTORY_MAX_PARALLEL=1` on a shared key | P2 | docs |
| 8 | GLM as lead followed the script through every stop | missing install, 403, dirty tree, conflict: each time it stopped and named the rule | keep a strong instruction follower as lead until P2 | P1 | ✅ cheatsheet |
| 9 | A `node_modules` symlink in the worktree tripped the patch guard | 3 of 18 rounds were deterministic fails on the same block, no code at fault | the guard ignores `node_modules` links the worktree setup creates; a block names the path and the rule | P2 | roadmap |
| 10 | Tokens not reported | the installed version predates D85; metrics show "not reported" | `usage.sh` after the upgrade, from the run metadata kept on the machine | P3 | ✅ D85 |
| 11 | Hand repairs not counted as interventions | 4 decisions in `decisions.tsv`, but the monorepo cleanup, the models reset, the ticket 14 marker and a `git rm` were done by hand | P8 counts manual commits; `metrics.sh` should count them too | P2 | roadmap |

## Result

15 tickets PASS, 20 contract assertions, behavior 20/20, health and steward PASS (23 quality-bar items). 18 rounds; first-pass review 86% (13/15). Human decisions: **4** (target 5; mission 2: 31). Cycle time: **7 hours** (mission 2: 9 days, factory work included). Lead GLM, workers Qwen, judges Gemma; one worker at a time on a shared key.
