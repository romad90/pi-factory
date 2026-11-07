# P25. What the first real job found

Status: queued, to build when the job ends (no factory change during a mission). Order: the trust metric and the rehearsal first (they prove the rest), then shorter instructions, then what cost a verdict or blocked the loop.

The job: a one-line refactor job on a TypeScript library inside a monorepo, run on the installed package (D105–D112). The architect step, the strategy critic, stacked job branches and the quota pause all ran for real. What broke, each with its fix:

## First: measure trust, rehearse the real environment

Source: Lauren Tan with Matt Pocock (2026): autonomy is climbed rung by rung, and each rung is earned by verification and by removing the reasons an agent needs a person.

- **A. Interventions per mission, planned and unplanned.** This job needed the person about fifteen times: four were planned gates (strategy, contract, tickets, MR); the rest were the factory's own environment (missing format docs, Stryker against the links, a missing verdict file, stray files, a committed report, quotas, a dirty tree). `factory learn` gets the column, from `decisions.tsv` and a new record each time `next.sh` returns `blocked`, `escalate` or `paused`. It is the trust metric: every fix below should lower the unplanned count, and the next job shows whether it did.
- **B. A dress rehearsal in CI.** 378 tests passed and the first real job still found these bugs: the tests use a simple project, the job ran in a module of a monorepo, on the installed package, with Stryker and symlinks. A CI job runs a whole scripted job (fake models) on a fixture monorepo in package mode with a Stryker done command, every release. Most items below would have failed it.
- **C. Frictions are pooled, then fixed in batches.** This document is that pool, written by hand. At the end of each job, `factory frictions` lists the job's unplanned interventions, grouped; the fixes come from the groups (root causes), not from the single incidents.

## Shorter instructions

The lead deliberated for paragraphs over ambiguous rules ("may I run `git status`?"); a frontier model needs the workflow, and scripts that print exactly what to do. Today: the lead prompt 914 words, the architect agent 957, the worker brief 647, briefs and agent files about 5,100 in all.

- **D. Rules move into scripts.** Each fix in this document ends with a script that prints the exact next command, and the prompt line it replaces is deleted. A rule a script enforces is not repeated in a prompt.
- **E. A word budget, with a ratchet.** `tests/prompt-budget.txt` holds the word count of the lead prompt, each agent file and each brief; the tests fail when one grows past it. Targets for this release: lead prompt under 450 words, architect under 500, worker brief under 400. A prompt that grows must name the failure it prevents.
- **F. Workflow, not implementation detail.** Prompts keep the steps and the stops; commands, paths and formats live in the scripts and the format docs they already point to.

## Autonomy: two-way doors first

A mission that only adds tests (a pin mission) is the most reversible kind. When A shows its contract and tickets needed no correction, those approvals fold into the strategy approval for that intent first (item 12). MRs stay with the person: merging is the team's.

## Must fix

1. **A verdict is a file, or nothing.** A reviewer reported PASS and wrote no verdict file; `collect.sh` ran before any file existed and only said "no verdicts". Fix: a judge run that ends without its file is re-run once, then stops the mission; `collect.sh` waits for the file (short timeout) and says where it looked.
2. **Agents write only where they may.** A judge saved command output to seven files at the project root (`git diff > diff.txt`), which dirtied the tree and blocked the next ticket's worktree. Fix: each judge and the lead get `.scratch/<mission>/tmp/`; the command guard refuses a redirection to a file outside `.scratch/` for roles that don't write code.
3. **Verdict paths are absolute.** Briefs give relative paths (`.scratch/<m>/verdicts/…`), which depend on where the agent runs; in a monorepo that is not always the project. Fix: briefs carry the project root's absolute path.
4. **Stryker and the factory's links.** Stryker's sandbox copy treats a symlink to a folder as a file and dies (`EISDIR`) on the package's links (`.factory/briefs`, `.factory/skills-pin`, `scripts/factory`). Fix: the strategy check requires `--ignorePatterns "/.factory,/scripts/factory"` on a Stryker done command in package mode, and the architect's brief shows it. (A repeated `--mutate` is already refused, #114.)
5. **The factory's own output stays out of `git status`.** Stryker writes `reports/`; a mission that runs it dirtied the tree. Fix: link/onboard adds the tool output folders a done command writes to the local exclude.

## Should fix

6. **A person's edit is committed for them.** After `/factory-decide`, an edit to a spec under `.scratch/` stayed uncommitted and blocked the wave. Fix: `human.sh decide` and `approve` checkpoint the mission folder.
7. **Clean-tree refusals list the files.** "Commit or stash changes" left the lead deliberating. Fix: print the `git status --short` lines and the command to run.
8. **`/factory-approve <job>`** after the strategy says which mission waits and for what, instead of "no spec".
9. **A lead that hits the quota leaves a trace.** The pause works when a launched agent fails; when the lead's own call fails, nothing records it. Fix: `next.sh` reads the last gateway error from the session and says "wait until HH:MM".
10. **Critic cost.** One strategy-critic run read 2.7M input tokens (it read installed packages to verify a claim). Fix: a token budget per critic run, and evidence by citation rather than whole-file reads where a line range does.
11. **A done command is tried before approval.** The architect wrote a Stryker command it never ran. Fix: at strategy time, run each done command in a check-only form where the tool has one (`--dryRunOnly`).

## Measure, then decide

12. **Mission gates under the strategy approval.** Contracts and tickets written from an approved strategy needed one change from the person in this job (a port note). If the next job confirms it, contract and ticket approvals fold into the strategy approval (the north star: one approval per job).
13. **Lead thinking level.** The lead ran at medium, then low, with no rule broken at low; thinking tokens count against an output quota. Default the lead to low.
