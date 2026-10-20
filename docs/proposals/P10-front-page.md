# P10. Front page: every subagent, at every stage, on one page

**Status:** draft · **Effort:** M · **Depends on:** nothing to start; P2 makes the events complete

## Problem

During a mission the human sees the lead's chat, and nothing else. Mission 2 showed what that costs:

| What happened | What the human had to do |
|---|---|
| A worker ran 36 minutes, "no activity for now" | Guess whether it was thinking or hung; open another terminal to tail its log |
| A wave timed out | Hunt for a worktree with `ls -t`, `git worktree list`, `grep` |
| The lead stopped at `STEP: build` and later invented a report | Read the chat, then check `git log` and `next.sh` by hand to learn the real state |
| Four tickets escalated | Ask for a shell loop to see why each one failed |

Each of these is a question the files already answer. Nobody shows the answer.

## What others built

Eleven open-source factories were read for this ([ideas to borrow](ideas.md), October 2026 scan). Their pages agree on the essentials:

- **The page only reads.** Symphony's spec: the dashboard is never needed for correctness. Atelier's cockpit only writes a cancel flag.
- **One snapshot, many views.** Symphony serves the same `snapshot()` to the page, a JSON API and a terminal UI.
- **Signal, then refetch.** sgai and Mastra push a tiny "something changed" event (SSE) and the page refetches one state document, with polling as fallback.
- **Stages as a rail, agents as rows.** DoorDash's phase rail (done, current, upcoming, *held* on a human); Symphony's one row per running agent with its last event in plain words; Gas Town's last-activity colour (green under 5 min, yellow under 10, red after).
- **No server at all is enough to start.** zazencodes' factory for Claude Code ships one `dashboard.html` served by `python3 -m http.server`: it lists the job folders, reads each `job.json` and the first line of each review file, and polls every 2 seconds. Jobs move across stage columns as cards; review chips pulse while waiting and fill in as verdicts land; jobs that need a human stand out.
- **Health as findings with evidence.** Mastra's supervisor computes "stuck", "stalled", "waiting on a human" from rows, each with evidence and a suggested repair; a model only explains them.

## Proposal

### 1. Events and one snapshot

Scripts append one line per event to `.scratch/<mission>/events.jsonl`: `next.sh` (step), `workflow.sh` (wave started, agent, model), `integrate.sh` and `collect.sh` (gate and verdict results), `human.sh` (asked, auto-answered, decided). Each line: time, mission, stage, ticket, role, model, round, event, details.

`status.sh <mission> --json` derives `state.json` from those events and the files already there (verdicts, markers, `decisions.tsv`), the way `next.sh` derives the step. Nothing new to keep in sync: delete `state.json` and it comes back.

### 2. The page

Start with no server, as zazencodes does: `scripts/factory/front.html`, opened through any static server (`python3 -m http.server` from the repo), reads `state.json` and polls every 2 s. `status.sh --json --watch` rewrites `state.json` when the mission's files change. If polling proves too slow or too heavy, `front.mjs` (a small Node server, no dependencies) adds an SSE route that sends `reload`, with polling kept as fallback. Read-only either way. Local by default (`localhost`), so it works on the user's machine with nothing to host; P6 later hosts the same page for a team.

Layout, top to bottom:

1. **Phase rail:** spec → contract → tickets → build → integrate → review → validate → MR, each done, current or upcoming, *held* when a human is needed.
2. **Needs you:** the human queue (questions, escalations, approvals) and the intervention count against P8's five.
3. **Subagents now:** one tile per running subagent: role, ticket, model and thinking level, round, elapsed, turns and tool calls, tokens, last action in plain words ("ran npm test", "edited a test file"), and the age of the last event in Gas Town's colours.
4. **Tickets × stages:** one row per ticket, one column per stage, with the round, the last verdict and its first blocking line, and a link to the log.
5. **Health findings:** worker quiet for more than 10 minutes, round failing like the last one (P9), worktree without a draft patch, decision waiting more than a day, each with its evidence and the command that fixes it.

### 3. Live worker activity

Workers run through pi-subagents, which writes each run's output under its async run folder. `status.sh` reads the newest lines of each running worker's log for the last action, turns and tokens. If the log format proves unstable, the tile falls back to what the scripts know (started, model, elapsed) and says so.

## Trade-offs

| For | Against |
|---|---|
| The human sees the real state from files, not the lead's account of it | Another surface to maintain. Kept small: one page and one snapshot script, tested from fixtures; a server only if needed |
| No database, no build step, nothing hosted: works offline, behind the corporate proxy | No history beyond the mission's own files; trends wait for P6 |
| The same snapshot feeds the page, a terminal view and P6 | Reading pi-subagents' logs ties tile details to its format; the tiles degrade, the page doesn't break |
| Health findings catch a stuck worker in minutes, not hours | A finding can be noisy; thresholds live in `commands.env` |

## Plan

1. `events.jsonl` written by the scripts; `status.sh --json` snapshot; tests from a fixture mission. **S**
2. `front.html` on a static server: rail, needs-you, tickets × stages. `front.mjs` with SSE only if polling falls short. **M**
3. Subagent tiles from pi-subagents' run logs, with the fallback. **M**
4. Health findings with evidence and the fixing command. **S**

## Open questions

- SQLite (Atelier, SSSF) or JSONL? Proposed: JSONL in the mission folder, committed with the rest; SQLite only if the page gets slow.
- Should the page ever write? Proposed: no in this proposal. Decisions stay in `/factory-decide`; P6 adds buttons that call the same scripts.
- One page per mission or per repo? Proposed: per repo, missions as tabs, since a repo rarely runs more than one.
