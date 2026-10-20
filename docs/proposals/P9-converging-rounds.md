# P9. Rounds that converge: reproduce first, carry what was learned, doubt the contract early

**Status:** draft · **Effort:** M · **Depends on:** nothing to start; P2 makes steps 3 and 4 simpler

## Problem

A fix round should get closer to green than the one before. In mission 2 it often didn't. On 19 October, 4 of 10 tickets (02, 03, 04, 07) had escalated after three rounds, while 05 and 06 passed on round 1. Looking at what each round started from:

| What happened | Evidence | Why it matters |
|---|---|---|
| A round starts almost from scratch | The fix-round brief gives the worker the verdict and nothing else: not what the last worker tried, ruled out, or where it stopped | Round 2 can repeat round 1's dead end |
| A worker fixes before seeing the failure | Round 1 of 08 handed over a test using `workerModule` and `MockMongo` without declaring them: 5 `ReferenceError`s at integration | A fix that never ran red can't be known to fix anything |
| A round that changes nothing still costs a round | Escalation counts rounds, not progress; two rounds failing on the same tests look like two attempts | The third round is often spent where the second one was |
| The contract's own mistake shows up as code failures | 05's test logs that a contract literal "is unreachable under its own Given": only visible in test stdout | Several tickets escalate one by one for one wrong line in the contract |
| A worker hands over without its self-check | On 20 October, 02, 03, 04, 07 and 08 escalated after three rounds on test-writing mistakes the self-check would have caught: `beforeEach` not imported, the real `process.exit` called, mocks not reset between runs, one unused variable. The brief asks for the self-check; nothing makes it happen | The same mistake costs three rounds and a human decision |
| An agent talks itself past a check | The lead wrote "Given time, I will assume lint now passes", then reported a self-check PASS and an integration that never ran | The cheapest failure to prevent is a sentence |

Two outside projects arrived at the same answers independently: [Machinist](https://github.com/owainlewis/machinist) passes handoff notes between runs and detects runs that make no progress; [afonsoft/skills](https://github.com/afonsoft/skills) (MIT) makes its `diagnose` skill refuse any fix before a command reproduces the failure, and stops after three failed fixes to question the design. Neither is adopted as a tool: both are prompt-driven where the factory's loop is scripts ([ideas to borrow](ideas.md)).

## Goal and measure

- **Rounds per passed ticket** below 1.5 (mission 2: about 2).
- **Escalations at round 3** below 1 in 10 tickets (mission 2: 4 in 10).
- No round spent repeating the previous round's failure: a ticket whose failure is unchanged escalates at round 2.

`metrics.sh` reports all three from the verdicts and the journal.

## Proposal

Five steps, each a script change plus a line in a brief. None needs a new agent.

### 1. Reproduce first (fix rounds)

From round 2, the worker brief asks for the failing command first: run it, see it red, then fix, then see it green. The report ends with `REPRO: <command>` and the self-check line. `collect.sh` treats a fix-round report without a `REPRO:` line as it treats a verdict without `Result:` (D69): sent back once, not a round.

Borrowed from afonsoft's `diagnose` ("no fixes without a red loop"). Cost: a few turns; saves the round where the fix never touched the failure.

### 2. A journal carried between rounds

Every worker report ends with a short `## Journal`: what was tried, what was ruled out and why, where it stopped. A script appends it, with the round number, to `.scratch/<mission>/journal/<ticket>.md`. The fix-round brief adds that file to what the worker reads, next to the verdict and the draft patch (D73).

Three lines a round, written by the agent that knows, read by the next one. Borrowed from Machinist's handoff notes and afonsoft's diagnostic journal.

### 3. No progress, no third round

`collect.sh` and `integrate.sh` keep a failure signature per round: the failing test names and the new lint keys, sorted. When round N fails with the same signature as round N-1, the ticket escalates now, with both rounds attached, instead of spending round 3. Each round's tokens go to `usage.tsv` (Machinist), so the cost of a stuck ticket is visible.

### 4. Doubt the contract when escalations cluster

Two signals:

- a worker or reviewer that finds a contract line it cannot satisfy writes `CONTRACT DOUBT: <assertion id>: <why>` (the 05 case); `collect.sh` gathers them in `.scratch/<mission>/contract-doubts.md`;
- two or more tickets escalated in the same mission.

Either way, `next.sh` puts the doubts first and proposes one amendment (`/factory-amend`) before any per-ticket decision. One decision instead of four. Borrowed from afonsoft's "three failed fixes: question the design".

### 5. Rationalizations named in the briefs

A short table in the worker and reviewer briefs (and the lead's, until P2):

| If you're about to write | Do instead |
|---|---|
| "I'll assume … passes" | Run it. A check you didn't run is a FAIL |
| "The tests probably pass" | Run `self-check.sh` and quote its last line |
| "This is close enough to the contract" | Quote the assertion; if it can't be met, `CONTRACT DOUBT:` |
| "I'll fix the test instead of the code" | Only if the test contradicts the contract; say which line |

Borrowed from afonsoft's "common rationalizations" tables. Costs nothing; the guard (D71) and P2 remain the real fix for the lead.

### 6. The script runs the self-check, not the worker

After each worker, the wave runs `self-check.sh` in its worktree itself. On FAIL, the same worker session gets the output and one more turn budget to fix it (correction in the same session, as Super Simple Software Factory and Atelier do); a second FAIL hands the patch to integration as today. A worker can no longer hand over red work by skipping the check, and the cheap fix happens before a round is spent.

### 7. Ticket notes from the human after an escalation

When tickets escalate on the same mistakes, the human adds one `## Notes from rounds 1-3` section to the tickets (the pitfalls, with the passing tickets to copy) and resets them. On 20 October this was one decision for five tickets. `next.sh` suggests it when the escalated verdicts share an error, and `reset-ticket.sh --note <file>` appends the note and resets in one step.

## Trade-offs

| For | Against |
|---|---|
| Fewer rounds and fewer escalations, so fewer tokens and fewer human decisions (P8) | Longer worker reports. Kept to a few lines, and the journal replaces re-reading the code |
| A contract mistake becomes one decision, early | A `CONTRACT DOUBT:` can be wrong or lazy. It never changes the contract: it puts a question to the human with its evidence |
| Early escalation at round 2 saves a full worker run | A real second attempt that fails the same way for a different reason escalates early. The human sees both rounds and can reset the ticket for one more |
| Every step is a script with a test | The signature only sees test names and lint keys, not why they fail. Good enough to detect "nothing changed" |

## Plan

1. `REPRO:` in the fix-round brief; `collect.sh` sends back a report without it. **S**
2. Journal: report section, append script, brief line. **S**
3. Failure signature per round; early escalation; `usage.tsv`. **M**
4. `CONTRACT DOUBT:` marker, `contract-doubts.md`, clustered escalations in `next.sh`. **S**
5. Rationalization table in the briefs. **S**
6. The three measures in `metrics.sh`. **S**
7. The wave runs `self-check.sh` after each worker and corrects in the same session once. **M**
8. `reset-ticket.sh --note`; shared errors across escalated verdicts suggest it. **S**

Steps 7, 1, 2 and 5 first (7 removes the most rounds): they change only briefs and one check, and could ship before mission 3.

## Open questions

- Should a `CONTRACT DOUBT:` pause the ticket, or let it continue while the human decides? Proposed: continue; the doubt is shown at the next human step.
- Should the journal be capped? Proposed: the last three rounds only, to keep the brief's prefix cacheable.
- Early escalation at round 2: always, or only for L tickets? Proposed: always; measured on mission 3.
