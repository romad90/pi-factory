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

## Spike results (October 2026)

Run in a scratch folder with Pi 1.3.0, pi-subagents 0.76.1 and Pi Durable 1.3.0 (`npm install --ignore-scripts`), against a fake OpenAI-compatible gateway, Node 22 (`node:sqlite` present). Status: **step 1 done; step 2 built as `run.sh` (D91).**

**Headless works, and the lead needs no model at all.**
- `pi -p --mode json` runs a generated workflow file and prints one JSON event per line; the `subagent` call's `tool_execution_end` event carries the workflow's return value in `result.details.workflow.value`, the per-child results, usage and the run ids. A failed workflow comes back as `isError: true` with the error text.
- `pi -p` waits on an open stdin: run it with `</dev/null`, or it hangs.
- The workflow path must look like a path (`./.scratch/…`): a bare name is read as a named workflow resource and refused.
- pi-subagents exposes no programmatic "run this workflow" entry point (its `runWorkflowScript` is internal, and the `/run` command runs one agent, not a file). But a Pi extension can register a provider whose answers are code (`createFauxCore` from pi-ai). `scripts/factory/driver.mjs` answers with exactly the call the lead is allowed to make, then ends the turn. With it, the fake gateway received **only** the child agent's request: no lead model, no lead tokens, no lead quota, nothing to improvise.
- The driver loads from any folder: Pi resolves `@earendil-works/pi-ai` for extensions.

**`--approve` is what loads the guard; it approves no tool call.** Pi's help: "Trust project-local files for this run". Headless, an untrusted project's own `.pi` files (extensions, agents) are not loaded. Checked with the factory guard copied into a scratch project, a child agent whose fake model runs `git push origin main`, and the driver making the lead's call:
- with `--approve`: the guard loaded and blocked the child's `git push` ("git push (the human pushes; CI gates): blocked by the factory guard"); it also blocked the driver's own call when the workflow path was not a generated one (`./wf.js`), and let it through for `./.scratch/<mission>/workflows/<…>.js`;
- without it (`--no-approve`, or no flag): the guard did not load and the child's `git push` **ran** (it failed only because the scratch repo has no remote).
So `run.sh` always passes `--approve`, and runs in the project the human installed and trusts. Pi has no per-tool approval prompt to bypass; `--approve` changes which project files load, nothing else.

**Pi Durable keeps its promise on crashes** (`openNodeSqliteStorage`, a scripted model, a tool that appends to a file then sleeps 4 s, `kill -9` at 2.5 s, reopen and `resume()`):
- a tool without `replay` ran **once**; after the restart the model got "Tool step was interrupted and may have partially run";
- the same tool with `replay: "safe"` ran **twice** (it reran after the restart), as documented;
- re-submitting the same input with the same `requestId` after the restart did not admit it again.

**Decision:** the loop is bash (`run.sh`), the runner is `pi -p --mode json` with the driver. Pi Durable is not needed for this step: every factory script already resumes from the mission's files, so a killed `run.sh` is simply run again. It stays the candidate engine for P12 (approvals from a phone, a live view for the cockpit), behind the same runner interface, once P12 is accepted.

## Plan

1. Spike: run one generated workflow headless and read its result. If it fails, stop here and decide the fallback. **S**
2. `factory-run.sh` covering every `next.sh` step, with the provider-error and pause paths. **M**
3. Tests: the end-to-end test drives `factory-run.sh` with a fake subagent runner. **S**
4. `/factory` stays, as a thin wrapper that calls the script and shows its output. **S**

## Open questions

- ~~Which headless entry point does pi-subagents support today?~~ `pi -p --mode json` with the driver extension (spike above). Stable across minor versions: to check on each upgrade; the test drives `run.sh` with a stand-in for pi that checks the flags.
- Should `factory-run.sh` notify on every human step (it does today through `next.sh`), or only on stops?
