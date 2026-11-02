# P23. Gates that can't be fooled: checks in code where code can decide, and every gate's recall measured

Status: proposed, after mission 6. Depends on D98 (bench), D97 (archive), P14.

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

## Outside checks

- Mission 6's escape replayed on the bench: today's gates miss it; with `surface` typed as a script check, it fails at validation.
- `bench.sh recall` on the corpus before and after: the table is the evidence for each gate change.
- The next mission's retro: escaped defects (found after the MR by any check or person) is the headline metric, target zero.

## Not doing

- A model as the factory's manager or as a gate's final word on a property code can decide. A better model lowers a fault's rate, never its class.
- Mutation testing inside the loop: Stryker stays a human step after validation until its run time per mission is measured.

---

## Release plan: what goes into the next release

From missions 4–6 and their retros, in order. Each line is one PR, merged by the human, measured on the next mission.

**Reliability (P23)**
1. ✅ Verdict sent back on a format slip; skeleton in every verdict-writing brief (#97).
2. ✅ No checkpoint on a detached HEAD; reattached when safe (#97).
3. Bench: no hang (no supervisor in a bench run), case worktrees outside `.git` (jest ignored them and the tests gate passed on zero tests), a time limit and progress lines per case. On branch `fix/bench-no-hang`, to finish.
4. Typed assertions and the five script checks.
5. Seeded-fault corpus, `bench.sh recall`; mission 6's escape is case 1.

**Measurement**
6. Health baseline carries its factory version; the duplicate counter skips generated declarations (`types/`, `*.d.ts`), which made every duplicate in one project a false positive.
7. Mutation rule: no new surviving mutant.
8. Lead tokens in the mission cost; decisions by kind; idempotent approvals.
9. Retros saved under the repository's name, not the worktree folder's; `Area` column; `learn` groups by it; old-format retros read or flagged.

**Tooling and cockpit**
10. `mr.sh`: the title from the spec when `pr.md` has none; `--help`.
11. Cockpit: QUIET only for running agents; MR count from `mr.url`; workers labelled by ticket.
12. `doctor`: warn on `NODE_TLS_REJECT_UNAUTHORIZED=0`; warn when user-level skills shadow the factory's (`~/.agents/skills`) and differ.
13. Guard: block reads of `~/.netrc`, `~/.git-credentials`, `~/.npmrc`.
14. Tools that copy the project tree (mutation testers) skip the factory's links: an ignore hint written by `factory link`.
15. A complete mission text skips the grilling and goes to the spec; the grilling asks only what is missing.

**Cost (P20, needs the gateway)**
16. Prompt caching for the fixed prefix, if the gateway supports it (0% cached in every mission so far).
17. Reviewers stop browsing the factory's own scripts: `scripts/factory` hidden from agents like the instrument.
18. A mechanical loop guard: the same tool call three times in a row, or a supervisor call with no reply, ends the run with a status.
19. Tools per role: list what each agent used in the archive, drop the rest, measure the fixed tokens before and after.

**Ideas, not yet scheduled**
- A judge from another model family, admitted only through `bench.sh recall`.
- Pi upgrades (1.5 is out) tested on the bench before any mission uses them.
- Escaped defects as incidents: each one becomes a seeded fault, so the corpus grows from real misses.
