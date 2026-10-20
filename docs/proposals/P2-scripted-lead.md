# P2. The lead becomes a script

**Status:** draft · **Effort:** M · **Depends on:** nothing

## Problem

The lead's job is fully deterministic. It runs `next.sh`, reads one line, runs the matching script, passes a file path to `subagent`, integrates the result, and repeats. It decides nothing: every decision belongs to a script or to a human (D32, D33).

Yet the lead is an LLM, and in mission 2 most of the incidents that a human had to undo came from it:

| What the lead did | Cost |
|---|---|
| Asked its question through `echo`, kept going, wrote a test file during the interview | ~4M tokens, a file to delete |
| Added `.scratch/` to `.gitignore` and committed it | Every checkpoint failed until a human found it |
| Recorded a failed round on a provider error, after being told not to | A round lost, reset by hand |
| Announced "we need to run doctor" and ended its turn | A human nudge per step |
| Edited `src/` outside any ticket (mission 1 and 2) | Changes to revert |

Each rule added to its prompt reduced one failure and left the others. A different model fixed some and caused new ones (message order, thinking levels). The pattern doesn't converge, because the problem is the tool, not the instructions.

## Proposal

Replace the LLM lead by **`factory-run.sh <mission>`**: the same loop as `.pi/prompts/factory.md`, in shell.

```
loop:
  step = next.sh <mission>
  case step in
    contract|tickets|validate|steward|build|review)
      file = workflow.sh <mode> <mission>
      run the workflow headless, collect its result as JSON
      integrate / record / collect, exactly as the prompt says
    human steps)
      print the status and the NEXT line, notify, exit 0
  esac
```

LLMs stay where judgment is needed: workers, reviewers, critic, steward, contract author, ticket writer. The interview stays in a Pi session with a human, which is a conversation and not orchestration.

Provider errors, rounds, pauses, the 70% context rule and the watchdog become plain code paths. They can't be forgotten or reinterpreted.

**Prerequisite to verify first:** pi-subagents must be callable without an interactive lead, with a workflow file and a JSON result (Pi's print or RPC mode, or a small Node entry point using the package directly). If it can't, the fallback is a minimal lead prompt with one tool call per turn and no free text, and the script checks every step it takes.

## Trade-offs

| For | Against |
|---|---|
| A whole class of failures disappears: improvisation, forgotten rules, edits outside its role | Less flexible: a situation the script doesn't know stops the mission instead of being handled. That's the correct default for a factory, but it will stop more often at first. |
| No lead model, no lead quota, no lead context to manage | Depends on a headless entry point into pi-subagents, which may not be a stable API. Pin the version (D29) and test the entry point in CI. |
| Testable: the loop gets unit tests like every other script | The human loses the chat view of the mission. Mitigation: `factory-run.sh` prints the same status lines, and `next.sh` stays the way to see where it stands. |
| Cheaper: the lead resent its whole history on every turn | |

## What it unlocks

- **Unattended runs.** A mission that runs from a cron job or a webhook needs a loop that doesn't drift. That's the precondition for the maintenance lane running in the background, and for P4.
- **Reproducible missions.** The same state gives the same next action, every time.
- **Lower cost per ticket.** Mission 2's lead consumed more tokens than some workers.

## Perspective

This is the step from "an agent that runs the factory" to "a factory that runs agents". Every reliable orchestration system separates the control plane (deterministic) from the workers (where the variance lives). The factory already did it for decisions (scripts decide rounds, coverage, verdicts); this finishes the job.

## Seen elsewhere

The October 2026 scan ([ideas](ideas.md)) found the same split in every factory that runs on more than one model: Super Simple Software Factory and Atelier (Python owns the graph, every phase starts as failed, agents return a typed envelope that code checks), DoorDash's orchestrator (fixed phases in Go, the harness writes the verification report), Bernstein and Mastra (deterministic scheduler, stages as data). SSSF and Anneal drive Pi headless with `pi -p --mode json`, which answers the first open question below.

## Plan

1. Spike: run one generated workflow headless and read its result. If it fails, stop here and decide the fallback. **S**
2. `factory-run.sh` covering every `next.sh` step, with the provider-error and pause paths. **M**
3. Tests: the end-to-end test drives `factory-run.sh` with a fake subagent runner. **S**
4. `/factory` stays, as a thin wrapper that calls the script and shows its output. **S**

## Open questions

- Which headless entry point does pi-subagents support today, and is it stable across minor versions?
- Should `factory-run.sh` notify on every human step (it does today through `next.sh`), or only on stops?
