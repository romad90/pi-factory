# P23. Gates that can't be fooled: checks in code where code can decide, and every gate's recall measured

Status: proposed, after mission 6. Depends on D98 (bench), D97 (archive), P14; section 7 on P2.

## North star: delegate, don't supervise

Chatting with agents is micromanagement: many tools, many conversations, every mistake corrected by hand, the human still in the loop. The factory aims at delegation instead: **one task, one owner; assign it and walk away; check the verifiable result at the end.**

Delegation needs three things, and the factory has only the second today:

1. **A complete assignment.** A spec that settles every decision. Mission 6 shows it works: a spec that left nothing open, and the factory asked the human no question.
2. **An owner.** The scripted loop and its agents carry the task to the end.
3. **A check that doesn't need the human.** Mission 6 also shows what is missing: every gate green, and the one escaped defect found only because the human ran a check by hand. "Walk away" is safe only when "verifiable" means a command.

Every item below is judged by one question: does it let the human assign once and come back to a result they can trust without watching the work?

## Problem

Mission 6 was the cleanest run so far: four tickets, all first-pass, no fix round, no question to the human, every gate green. One defect still got through every gate. A refactoring wrapped two public methods in a helper that returns `undefined` on error; TypeScript inferred `Promise<void | undefined>` instead of `Promise<void>`, so the package's published types changed. The contract had the right assertion ("the public surface is unchanged"). An agent judged it, compared export names, and passed it. The human's API Extractor run, a ten-second mechanical diff of the regenerated declarations, caught it after validation.

The retros of three missions say the same thing in other places:

- A verdict the gate can't parse stalled two missions (fixed in #97: sent back, skeleton in briefs).
- A validator left the checkout on a detached HEAD in two missions (fixed in #97).
- The health ratchet compared `skipped_tests` measured by two factory versions (1 → 0 with no test touched).
- A mutation score "no lower" failed a refactoring that weakened nothing: two mutants left the denominator, the same single survivor stayed.

None of these is a model being weak. Each is a property a program could decide, handed to a model or to a number that doesn't measure it.

## Principle

LLM agents fail Byzantine: wrong and confident, not crashed. The factory already follows the Simplex pattern for the loop (a deterministic state machine decides; agents only produce). P23 extends it to the gates:

1. **Program checking.** A property a script can decide is decided by the script. A model judges only what is left.
2. **Fail-stop.** Every component ends in a bounded time with an explicit status. Silence is failure.
3. **Measured recall.** A gate is trusted for a fault class only as far as its measured detection rate on seeded faults of that class.
4. **Measured diversity.** A second judge is worth adding only when its misses are measured not to coincide with the first's (Knight and Leveson, 1986: independently built versions fail together far more often than independence predicts).

## Design

### 1. Typed assertions

Every contract assertion gets `**Checked by:** script` or `**Checked by:** judge`. The contract author proposes; the critic challenges any `judge` assertion a script could decide.

Script checks ship with the factory, each a small command with a PASS/FAIL exit and a log line as evidence:

| Check | What it compares |
|---|---|
| `surface` | declarations regenerated from source (tsc, or the language's equivalent) against a committed report; any diff fails |
| `frozen-tests` | `git diff --stat <base> -- <frozen paths>` is empty, and the frozen suite's count and result equal the baseline |
| `paths` | the mission diff touches only the paths in scope |
| `nesting` | `health.sh details` no longer lists the named files under `deep` |
| `mutants` | surviving mutants after ⊆ surviving mutants before, matched by file, line and mutator (not a score ratio) |

The validator still writes the behavior verdict; script assertions arrive in it already decided, with their logs, and the validator may not overturn them.

### 2. Seeded-fault corpus and gate recall

A corpus of faults in the shapes the missions actually produced, each a small patch applied on a real bench case:

- a widened return type (mission 6's escape is case 1)
- an edited or deleted frozen test, a new `.skip`
- an added or removed export
- a read moved from call time to import time, or the reverse
- a file outside the scope
- a verdict without its header

`bench.sh recall` sends each seeded case to each gate and prints a table: gate × fault class → caught, missed, false alarm. For model judges, it also prints how often two judges miss the same seeded fault.

What it decides:
- Whether a new judge (another model family) earns its place: it must catch a class the others miss.
- Whether a tier can merge with one approval (P22): only when the gates' combined recall on that tier's fault classes is above a threshold set in advance.

### 3. Measurement that measures

- The health baseline stores the factory version that measured it; the ratchet refuses to compare across versions and asks for a re-baseline.
- Mission cost includes the lead: mission 6 spent 7.2M input tokens in the lead's own session against 2.1M in all subagents, and the cockpit counted only the subagents.
- Decisions carry a kind (gate, amendment, question); the target applies to questions only. A second approval of an approved gate is refused.
- `factory learn` groups findings by a fixed `Area` column the retro skill fills (`verdict-format`, `git-state`, `gate-coverage`, `cost`, `measurement`, `setup`, `cockpit`), not by word overlap, which missed every paraphrase.
- **Pinned models.** The lead ran on a `latest` alias the gateway can repoint at any time, so two missions or two bench arms may not have run the same model. The pre-flight already warns about floating aliases (D102); it becomes a refusal for any role, the profile names exact versions, and each run records the model the gateway actually resolved.
- **Human wait, measured.** The time from a human `STEP` to the decision is recorded per gate. Mission 6's 15-hour cycle was mostly waiting; machine time and human time are reported apart, which is the honest number for anyone deciding whether to adopt the factory.

### 4. The human's checks become commands

The weakest step in mission 6 was the human, not an agent: about three hours of preparation, retyped by hand, with some fifteen typing errors along the way (a misspelled method name, `2>1` for `2>&1`, misspelled config keys, a missing folder). And the one check that caught the escaped defect ran only because the human remembered it.

- `factory prepare <mission>` (before the spec): the green baseline (suites, tests, time), `health.sh details` and the churn of the past year, mutation testing on the candidate files with the scope cut (score ≥ 70%), the public API report regenerated and committed, a spec draft from the intent's template (refactor: frozen tests, frozen paths, done conditions, who checks what). Everything it measures is saved privately as the mission's baseline.
- `factory verify <mission>` (after validation): the same measurements again, compared with the baseline: API report identical, no new surviving mutant, frozen suite unchanged. PASS or FAIL with the diff, and the lines for the MR description.

Once the script checks of section 1 exist, `verify` runs inside the loop; until then it is the human's one command.

### 5. A release is a canary first

rc.39 to rc.42 went straight into a real project after the factory's own tests. A release candidate now runs the bench's cases (and `bench.sh recall` once the corpus exists) before `sync-mirror.sh` may install it in a project; a drop in pass rate or recall beyond the run-to-run noise blocks it. The same rule applies to Pi and pi-subagents upgrades.

### 6. The retro closes after the merge (built)

The lead writes the retro before the MR, so it never sees what came after: the human's checks (mission 6's escape is missing from its retro), the team's review comments, a defect found in use. `retro.sh close <mission>`, run after the merge, adds a section to the private retro:

- **The team's review comments, as candidate recall misses.** A comment a person had to leave is something the factory's reviewers did not say (the recall failure of an AI reviewer, as Faire measures it). It is a candidate, not a miss: a comment can be a preference or a question. The human labels each one `[miss]` or `[ok]`; labels survive a re-run. `factory learn` counts the labelled misses per mission. System notes, bots and the MR's author are left out.
- **Reverts** of the merged change: a guardrail metric. Throughput can rise while quality falls; a revert says so.
- **Escaped defects**, one line each, written by the person. Each one becomes a seeded fault in the corpus (section 2), so the corpus grows from real misses.

Precision (an agent's comment nobody acted on) does not apply yet: the factory's reviewers write verdicts, not MR comments. It does when P16 brings review into the forge.

### 6b. Friction from the transcripts (built)

An agent fighting its setup (a port in use, a tool missing, a guard refusal it retries around) spends tokens and reports success anyway. Uber lets agents report these "paper cuts" themselves; the factory reads them from the evidence instead: `factory frictions <mission>` lists, from the archived transcripts, the tool calls that failed, the calls repeated three times or more in a run, and the guard's refusals, grouped by cause across runs (digits folded, so port 3001 and port 3002 are one cause). The retro pack includes it. A cause seen in several runs is fixed in a brief, a setup step or a skill, and the next mission's frictions show whether the fix held.

### 6c. Old specs are dated intent (built)

Every mission leaves its spec in `.scratch/<mission>/spec.md`. Six months later it describes what was wanted then, not what the code does. The rule every role shares (`docs/agents/factory.md`): another mission's spec is intent as of its date; for current behavior, the code and its tests are the truth.

### 6d. No judge is trusted before it is calibrated (rule)

Scoring runs with an LLM judge (Warp's rubrics: redundant tests, verbosity, efficiency) assume the judge is right. Mission 6 had four judges agree on something false. Two rules before any judge's score drives a decision:

1. **Count before judging.** What a script can count is counted: efficiency is failed calls, repeated calls and tokens (`frictions`, `tokens`), not a rubric.
2. **Calibrate.** A judge is run on labelled cases first (the seeded-fault corpus, the labelled review misses) and its agreement with the labels is reported. A judge below the bar set in advance informs, never gates. Entry condition: a corpus of at least 20 labelled cases per dimension.

### 7. The lead's memory, bounded (P2 revisited)

All mission state is on disk; `next.sh` rebuilds it every step. The lead's long conversation therefore adds cost, not knowledge: every turn resends it, so its cost grows with the square of its length. A fresh lead session per `STEP`, started with the step's line and nothing else, bounds it to one step. This is P2's scripted lead, now justified by measured numbers; it is decided in P2, measured here (lead tokens per mission before and after).

## Outside checks

- Mission 6's escape replayed on the bench: today's gates miss it; with `surface` typed as a script check, it fails at validation.
- `bench.sh recall` on the corpus before and after: the table is the evidence for each gate change.
- The next mission's retro: escaped defects (found after the MR by any check or person) is the headline metric, target zero.
- Labelled review misses per mission (`learn`), and frictions per run, before and after each fix aimed at them.
- Preparation time and typing errors before and after `factory prepare`: mission 6 took about three hours.
- Lead tokens per mission before and after a fresh session per step.

## Not doing

- A model as the factory's manager or as a gate's final word on a property code can decide. A better model lowers a fault's rate, never its class.
- Mutation testing inside the loop: Stryker stays a human step after validation until its run time per mission is measured.

---

## Release plan: what goes into the next release

From missions 4–6 and their retros, in order. Each line is one PR, merged by the human, measured on the next mission.

**Reliability**
1. ✅ Verdict sent back on a format slip; skeleton in every verdict-writing brief (#97).
2. ✅ No checkpoint on a detached HEAD; reattached when safe (#97).
3. ✅ Bench: no hang (no supervisor in a bench run), case worktrees outside `.git` (jest ignored them and the tests gate passed on zero tests), a time limit and progress lines per case (#100).
4. `factory prepare` and `factory verify`: the human's checks as two commands (section 4).
5. Canary release: an rc replays the bench before it can reach a project (section 5).
6. Typed assertions and the five script checks (section 1).
7. Seeded-fault corpus, `bench.sh recall`; mission 6's escape is case 1 (section 2).
8. ✅ `retro.sh close` after the merge: review comments as candidate misses, reverts, escaped defects (section 6).
9. ✅ `factory frictions`: failed, repeated and refused calls from the transcripts, in the retro pack (section 6b).
10. ✅ Other missions' specs are dated intent (section 6c).
11. Judge calibration on labelled cases before any score gates (section 6d), once the corpus has 20 cases per dimension.

**Measurement**
12. Pinned model versions, the resolved model recorded per run; a floating alias refused, not only warned about (D102 warns).
13. Health baseline carries its factory version; the duplicate counter skips generated declarations (`types/`, `*.d.ts`), which made every duplicate in one project a false positive.
14. Mutation rule: no new surviving mutant.
15. Lead tokens in the mission cost; decisions by kind; idempotent approvals; human wait per gate.
16. Retros saved under the repository's name, not the worktree folder's; `Area` column; `learn` groups by it; old-format retros read or flagged.

**Tooling and cockpit**
17. `mr.sh`: the title from the spec when `pr.md` has none; `--help`.
18. Cockpit: QUIET only for running agents; MR count from `mr.url`; workers labelled by ticket. Read-only additions (P10 section 6): the next command with a copy button at every human step, and the new measurements; no button that runs anything yet.
19. `doctor`: warn when user-level skills shadow the factory's (`~/.agents/skills`) and differ. (TLS checks turned off are already reported, D102.)
20. Guard: block reads of `~/.netrc`, `~/.git-credentials`, `~/.npmrc`.
21. Tools that copy the project tree (mutation testers) skip the factory's links: an ignore hint written by `factory link`.
22. A complete mission text skips the grilling and goes to the spec; the grilling asks only what is missing.

**Cost (P20; P2 for the lead)**
23. A fresh lead session per step (section 7), measured on lead tokens per mission.
24. Prompt caching for the fixed prefix, if the gateway supports it (0% cached in every mission so far).
25. Reviewers stop browsing the factory's own scripts: `scripts/factory` hidden from agents like the instrument.
26. A mechanical loop guard: the same tool call three times in a row, or a supervisor call with no reply, ends the run with a status.
27. Tools per role: list what each agent used in the archive, drop the rest, measure the fixed tokens before and after.

**Ideas, not yet scheduled**
- A judge from another model family, admitted only through `bench.sh recall`.
- Pi upgrades (1.5 is out) through the canary before any mission uses them.
