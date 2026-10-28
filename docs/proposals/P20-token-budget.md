# P20. Token budget: every agent fits a known budget, measured before it is cut

**Status:** proposed; step 1 (measure) built with this proposal · **Effort:** M · **Depends on:** D97 (run archive), D85 (usage); changes no gate

## Problem

Mission 5 (a characterization mission on a TypeScript package, 14 tickets) stopped twice on provider limits, for two different reasons:

| Limit | What it counted | What happened | What fixes it |
|---|---|---|---|
| Requests per window (workers' and reviewers' keys) | calls | 4 workers, then 2 reviewers at once, emptied a 5-request window | fewer agents at a time (`FACTORY_MAX_PARALLEL=1`), a second route for the judges |
| **Tokens per window, per key** (the judges' key: 45,000) | **the size of each request** | the reviewer was refused with the window's quota untouched (`Remaining: 45000`): one request was over 45,000 tokens. Waiting can't fix that | smaller requests, or a bigger quota |

The second one is structural. A model keeps no memory between calls: every turn of an agent resends its whole conversation, so far: the brief, every file it read, every test log, every subagent report. Turn 1 of a reviewer is about 10,000 tokens; after one `jest --coverage` and a few files it passes 45,000. More quota helps, but the environments the factory must run in won't all give it, and nothing is free.

The design rule: **assume tokens are scarce; every agent fits a known budget per request.**

## What not to do first

Shorten the prompts. A controlled study on SkillsBench (40 tasks, 3 runs each, two models) found that skills shortened by up to 54% left the cost per task unchanged: instructions are a small, cached part of each request. Rewriting them with a model lowered success on the small model (42.5% to 29–37.5%). The tokens go elsewhere: to what accumulates during the run.

## Steps, each measured before the next

1. **Measure (built here).** `factory tokens <mission> [--budget N]` reads the run archive: per run, the size of every request (input + cache read + cache write, as the provider counted it), the largest one, the request the run would have sent next (the one a size limit refuses), and the tool results that filled them, largest first, by tool and by agent. The answer to "where do the 45,000 come from" becomes a table, not a guess.
2. **Cap tool output** (expected to be the biggest saving; step 1 decides). Test, lint and type-check runs return only the failures and a one-line summary; the full log goes to a file the agent reads only if it needs to. `self-check.sh` already tails its failures; the judges' "run the tests yourself" does not.
3. **Give each agent only what its job needs.** *(First part built: the worker and reviewer briefs carry the ticket and only its assertions, and tell the agent not to read the spec or the workflow files; workers run their own test files while working, the whole suite once in the self-check. Mission 5's data: every agent read the whole spec, 5.3k tokens resent on every later turn, and workers ran 28 to 45 turns.)* A reviewer reads the ticket, its assertions and the diff, not the whole spec; pointers to files instead of their content. A re-review after round 2 reads only the new diff (the code review practice from "How the Claude Code team does code review": diff-only re-review, no repeated findings).
4. **`maxTokens` sized per role, checked against each key.** Mission 5's judges reserved 32,768 output tokens per request (a value inherited from the model sheet) on a key with a 45,000-token window: every review was refused with the window untouched. Onboarding sets `maxTokens` per role; `factory budget` (and `doctor`) checks input peak + `maxTokens` against each key's window, with limits learned from the 429 messages the archive keeps; the probe stamp includes `maxTokens` and `contextWindow`.
5. **A hard budget per request.** `FACTORY_CONTEXT_BUDGET` (default to be set from step 1's data). `doctor` compares it with each key's limit when the provider reports one; `factory tokens --budget` flags runs over it; agents get the budget in their brief and summarize their notes into a file before crossing it.
6. **Fewer agents rereading the same thing.** The reviewer and its review axes read the same diff for every ticket. Whether one agent with both axes does as well is the fold experiment (one agent against two, archived missions, several runs each, on the bench, D98): decided by our data, not by vendor posts.

## Outside checks

- `factory tokens` on a mission's archive: the largest request per agent, before and after each step. A step is kept when it lowers it without lowering the validator's PASS rate or raising rounds per ticket (metrics, D97).
- The judges' 429s on a 45,000-token key: zero after steps 2 to 4, with the same model.

## Not doing

- Rewriting prompts or skills with a model to make them shorter (the evidence above).
- Smaller models for the judges to save tokens: family separation (D31) and judge quality come first; a judge that misses findings costs more than its tokens.
