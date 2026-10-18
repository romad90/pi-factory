# P8. Hands-off mission: the human decides, the factory does the rest

**Status:** steps 1–3 done (D65–D70), step 4 partly (metrics count human and auto decisions apart) · **Effort:** M · **Depends on:** nothing to start; P2 for the last step

## Problem

A factory the human has to babysit is not a factory. In mission 2, the human answered a question every few hours, applied patches by hand, fixed verdict headers, and lost a night to a worker waiting on a question the factory could have answered. Sorted by what the human actually did ([retro](../retros/mission-02.md), findings 30–40):

| What the human did | Examples | Should a human do it? |
|---|---|---|
| Fixed plumbing | no dependencies in a worktree, lost patch, dirty tree, uncommitted decision, misspelled mission name, quoting in `/factory-decide`, verdict without a `Result:` line | never |
| Repeated a rule the worker didn't have | "don't touch `src/`", "use the harness", "never `eslint-disable`", "an exit is not a no-op" | no: the answer was already settled |
| Repaired work by hand | applied a patch, removed a silencing comment, typed `any` | no: the worker should catch it before handing over |
| Protected the checkout from another agent | a second coding agent switched branches in the mission's folder | no: the pre-flight should refuse it |
| Made real decisions | lint scope, contract differences, approving the contract and tickets | **yes** |

Most interventions were in the first four rows. Each one also cost tokens: a failed round redoes a whole worker run.

## Goal and measure

At most **five human interventions per mission**: the spec, the contract (G1), the tickets, one or two real decisions, the MR. An intervention is a human entry in `decisions.tsv`, a manual commit in the mission, or a manual `/factory` relaunch. Mission 2 is the baseline; `metrics.sh` counts them from mission 3.

## Proposal

Five steps, by human time saved. Steps 1–4 are scripts on today's architecture.

### 1. Workers check their own work before handing it over

- **Dependencies in every worktree.** The worktree hook links the main checkout's installed dependencies (or runs the lock-file install command from `commands.env`), before the worker starts. A worker never has to ask.
- **Self-check before finishing.** The worker runs the same commands integration runs (lint against the baseline, tests, extra check) and the patch guard on its own diff, and fixes what fails. It finishes only when they pass, or stops with the reason.
- **Clean patch.** `locate-patch.sh` excludes dependency folders and links, whatever `.gitignore` says.

Removes: most failed rounds, every "install dev dependencies?" question, hand repairs of silenced checks.

### 2. Settled questions are answered without the human

Before a question reaches the human, `human.sh ask` runs a resolver, a script first:

- an option that changes a frozen path, `package.json`, the lint or test commands, or skips a check is refused, with the rule that refuses it;
- a question already answered in `decisions.tsv` gets that answer;
- what is left, and anything irreversible or about the contract, goes to the human.

Auto-answers are logged as `auto` in `decisions.tsv` and shown in the morning summary, so the human can overturn one. Questions that do reach the human are batched, with options and a recommendation, not one per night.

Removes: the questions whose answer was a rule the worker didn't read.

### 3. Mechanics repair themselves

| Today | Then |
|---|---|
| A verdict without a `Result:` line counts as a failed round | `collect.sh` sends it back to the reviewer once |
| A decision left uncommitted blocks the next wave | `human.sh decide` commits its entry |
| `/factory-decide` loses the split between answer and why, backticks run as commands | a fixed separator, text written without the shell |
| `/factory <typo>` starts a pre-flight on a mission that doesn't exist | refused, with the closest existing name |
| Another agent's changes or another branch in the checkout | pre-flight refuses: wrong branch, or changes outside `.scratch/` not made by the factory |

### 4. A run the human can leave

- Notify only when the factory is really stuck (a question that reached the human, an escalation, a gate red twice).
- A morning summary in the mission folder: what passed, what was auto-answered, what waits on the human, cost per ticket (tokens, rounds).

### 5. The lead becomes a script (P2)

The last source of drift: the LLM lead announces an action and stops, misspells names, mangles quotes, and is the largest token consumer. With steps 1–4, its job is pure routing; P2 makes it a script that calls a model only to write.

## Trade-offs

| For | Against |
|---|---|
| Human time goes to decisions only, the goal in [INTENT.md](../INTENT.md) | An auto-answer can be wrong. Only settled questions are answered (a rule or an earlier human answer), each is logged and shown, and nothing irreversible is ever auto-answered |
| Fewer failed rounds, so fewer tokens | Linking the main checkout's dependencies shares one install between worktrees. A worker that changes `package.json` is already refused by the patch guard; a lock-file install is the alternative where linking is unsafe |
| Each step is small and testable on its own | Five changes to land before mission 3. Steps 1 and 3 first: they remove the most interventions |

## Plan

1. ✅ Dependencies in the worktree hook; `locate-patch.sh` excludes them. **S** (D65)
2. ✅ Self-check in the worker brief and a `self-check.sh` it runs (commands + patch guard on its diff). **S** (D66)
3. ✅ Self-repairing mechanics (step 3 table), one test each. **S** (D67–D69)
4. ✅ Resolver in `human.sh ask`; `auto` decisions. Batched questions: not yet. **M** (D70)
5. Intervention count in `metrics.sh` (human and auto apart: ✅); morning summary; notifications. **S**
6. Scripted lead: P2. **M**

## Open questions

- Link dependencies or install from the lock file per worktree? Linking is instant and offline; installing isolates. Proposed: link by default, install when `FACTORY_DEPS_CMD` is set.
- Should the resolver ever use a model to match a question to an earlier answer? Proposed: no at first; exact rules only, measured on mission 3.
