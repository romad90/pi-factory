# P12. A durable runner: the mission survives a closed laptop, and the human answers from anywhere

**Status:** draft · **Effort:** M (spike S) · **Depends on:** P2 (this is one way to build it); P10 and P8 fit on top

## Problem

The factory's decisions are in code and its state is in files, but the loop that drives a mission is still a person, or a lead, sitting in a Pi session:

| What happens | Why |
|---|---|
| Closing the laptop or losing the cloud IDE tab stops the mission between two steps | The lead runs in an interactive Pi session; pi-subagents 0.76.1 has no headless entry point |
| A question waits until the human is back at that terminal | Questions are answered in the session that asked them |
| After a crash mid-wave, the human works out by hand what had run and reruns it | The scripts are safe to rerun from the files, but nothing reruns them |
| The cockpit (P10) can only poll files; the live worker view in the mockup has no source | Runs write their events to a log only the session reads |
| In mission 3, GLM as lead followed the STEP line well, but still a model reads every step | P2's problem, unchanged |

P2 proposes `factory-run.sh`. Its open question is the headless runner. In October 2026, Earendil released **Pi Durable** (`@earendil-works/pi-durable`, experimental, version 1.3.0 like Pi): a library that replaces Pi's agent loop with one that saves every step before running it and resumes after a crash. It answers P2's question and brings three things P2 didn't plan.

## What Pi Durable is

- **A library, not an application.** A Node program opens a *harness* on a storage (SQLite, JSONL, or memory for tests), creates *conversations* (each with its own instructions, working folder, model and tools) and *submits* inputs to them.
- **Everything is a saved task.** A model call, a tool call and a child task are saved before they run. `resume()` continues from the last checkpoint after a crash.
- **Each tool declares whether it may run again.** `replay: "safe"` reruns after a crash. The default doesn't: the model is told the call was interrupted, with whatever output was saved, and decides.
- **Approvals are saved once.** The first answer wins; a restart does not ask again.
- **Any client can attach.** A conversation's live view (finished entries, running tool output, queued inputs) can be subscribed to from a terminal, a page or a phone. Inputs submitted with the same `requestId` are admitted once.
- **It loads nothing on its own.** No `.pi` folder, no `AGENTS.md`, no skills: models, tools and instructions are passed in by code.

What it does not do: restore the environment (worktrees, shells), sandbox anything, lock a store across processes (one process owns a store), give exactly-once for side effects outside it, or provide subagents ready-made (it has child tasks and forks to build them on). It is about 15,000 lines, ships without tests, and its API is expected to change.

## Proposal

A small Node program, **`factory run <mission>`**, built on Pi Durable, is the scripted lead of P2.

```
harness = open(sqlite: .scratch/<mission>/run.db)
loop:
  step = task("next", replay: safe)            → next.sh
  case step:
    build|review|contract|tickets|validate|steward
      file = task("workflow", replay: safe)    → workflow.sh
      task("wave", replay: unsafe)             → run the workers (see below)
      task("collect", replay: safe)            → collect.sh
      task("integrate", replay: unsafe)        → integrate.sh (its markers make it safe to rerun; declared unsafe until proven)
    question
      approval(question.md)                    → waits; answered from the cockpit, the phone or the terminal
    human gate (G1, G2, MR)
      approval(gate)                           → same
    done → stop
```

- **The files stay the source of truth.** The run database only says which step the runner is on. Everything a step decides is in `.scratch/`, `state/` and the verdicts, as today. Delete `run.db` and the next start rebuilds its position from `next.sh`. If Pi Durable disappears, `next.sh` by hand still finishes the mission: the same test we apply to every borrowed tool.
- **Scripts are the tools.** The runner calls our scripts; it has no model of its own. A model appears only inside the workers and judges.
- **Questions and gates become approvals.** `resolve.sh` answers what it can first (D72, D82); what is left waits as an approval that the cockpit's "Needs you" screen and the phone can answer. The answer is still written to `decisions.tsv`.
- **The cockpit subscribes instead of polling.** The live view feeds the mission screen (active ticket, assertions, live tool calls, tokens from `usage.tsv`), borrowed from Factory's Mission Control.
- **Configuration is explicit.** Models per role, gateways and briefs are passed in from the machine's profile, which is what P11 needs anyway.

### The workers: two stages

1. **Keep pi-subagents for the workers.** The runner starts the generated workflow through Pi in JSON mode (`pi -p --mode json`, as SSSF and Anneal do) and reads its result. One change at a time: the workers are where the work is.
2. **Later, if stage 1 holds:** workers as Pi Durable child tasks, each in its worktree with its gate. This removes the pi-subagents dependency but rebuilds `parallel`, `gate` and `resume`, so it waits for evidence.

## Trade-offs

| For | Against |
|---|---|
| The mission runs while the laptop is closed; a crash resumes at the step it was on | Experimental, untested library; the API will change. Pin it, wrap it in one file, test the wrapper |
| No lead model: P2's failure class disappears | Node program to maintain next to the bash scripts |
| The human answers from anywhere; P8's interventions become asynchronous | One process per store: two runners on one mission must be refused |
| The cockpit gets a live feed for free | Needs npm access and Node with built-in SQLite on the work machine (to check behind the corporate proxy) |
| Configuration comes from code, which P11 needs | Gateways have to be configured in code; Pi's `models.json` is not read automatically |

## What it borrows

- **Pi Durable** (Earendil): saved tasks, replay classes, approvals saved once, attachable clients.
- **Durable execution** in general: record the intent before the act, the result after, and decide at restart from the record. Our `.integrated` marker and D81's commit check are already this, by hand.
- From the videos that presented it: a proactive agent that works, then waits for a human approval ("human near the loop"), and a self-healing loop from error to PR. Both are P4's director, with the runner underneath.

## Plan

1. **Spike, after mission 3, on a throwaway mission.** A runner of about 200 lines runs one ticket end to end: next → workflow (headless) → collect → integrate, the review question as an approval. Kill the process during the worker and during integration; restart; check there is no double integration and no lost round. Check npm access, Node's SQLite and a gateway model on the cloud machine. **S**
2. If it holds: the runner covers every `next.sh` step, with the provider-error and pause paths of P2. Tests with a fake worker runner. **M**
3. The cockpit reads the live view; the phone screen answers approvals. **S** (with P10)
4. Stage 2 (workers as child tasks) only if 1 to 3 hold over two missions. **M**

If the spike fails, P2 goes ahead as planned: `factory-run.sh` in bash, headless Pi in JSON mode, the cockpit polling files. Slower, no outside dependency.

## Open questions

- Does Pi Durable install and run behind the work network, with our gateways (`openai-completions`, base URL ending in `/v1`)?
- Is `pi -p --mode json` enough to run a pi-subagents workflow headless on 0.76.1 or 0.79.2?
- Where does the runner live: the cloud machine only, or also the Mac? One store per mission means one machine per mission.
- Approvals from a phone need the runner reachable from outside the machine: through the cockpit's host (P6), or not at all at first?

## Sources

- [How to build agents that survive crashes with Pi Durable](https://flaviocopes.com/pi-durable/)
- [What durable agent harnesses actually guarantee](https://redreamality.com/blog/pi-durable-agent-harness-durable-execution/)
- [Pi 1.0 adds MCP support and introduces experimental Pi Durable](https://letsdatascience.com/news/pi-10-adds-mcp-and-durable-harness-6241c6f7)
