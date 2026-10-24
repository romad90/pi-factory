# P10. Front page: every subagent, at every stage, on one page

**Status:** v1 built (D90): snapshot, page, zoom to the ticket; SSE, health thresholds and the phone view remain · **Effort:** M · **Depends on:** nothing to start; P2 makes the events complete

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

Factory's Missions (October 2026, closed product, from screenshots) adds the mission screen used in section 4: the active feature with its preconditions and expected behavior, a features checklist, a progress log, the active worker's live tool calls, and keys to switch views. See [ideas](ideas.md).


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

### 4. Zoom: from the leads to a line of the diff

The human's job across missions is supervising leads, not reading logs. The page is built as one zoom, each level one click or key from the next, the URL keeping where you are:

| Level | Shows | Opens from |
|---|---|---|
| **Leads** | every mission on the machine (one per repo or project): phase, lead or runner alive, open questions, interventions against five, tokens so far | the start page |
| **Mission** | Factory's Mission Control layout: the active ticket with its preconditions (`Blocked by`) and expected behavior (`## Assertions`), the ticket checklist (13/16), the progress log from `events.jsonl`, the active worker with its live tool calls, tokens and time | a lead |
| **Ticket** | its rounds, each with the journal entry (D84), failure signature, verdict and patch | a ticket in the checklist |
| **Verdict** | the review and its axes, blocking lines first, the question if one was asked and how it was answered | a round |
| **Log** | the worker's run log from the line that matters (the first failing test, the gate's output) | a verdict line |
| **Diff** | the commit the verdict reviewed, with the files the ticket named marked (D82) | the verdict |

Keys, as in Mission Control: `L` leads, `M` mission, `W` workers, `R` rounds, `Tab` next pane, `Esc` up one level. On a phone the page shows only **Needs you**: each question with the resolver's recommendation, answerable in one tap once P12 (or P6) gives the page a way to write.

The mockup is the "Factory Cockpit" canvas (desktop and phone boards).

### Design principle: two users, both served efficiently

The page has two users with different questions, and neither may pay for the other's views:

| | Product engineer (follows and steers the work) | Factory engineer (tunes the factory) |
|---|---|---|
| Question on arrival | What needs me now? Where is my work, and is it moving? | Where does the factory lose time, money or quality, and did my last change help? |
| Unit | a mission, a ticket, a decision | a role, a model, a pattern, a factory version |
| Time scale | now, today | across missions, weeks |
| First screen | Inbox (needs-you across repos), then leads → mission → ticket | Dashboard: cost per merged MR, human decisions per MR, first-pass rate, trend since the last factory change |
| Typical action | answer, approve, open the MR | read a pattern, run a benchmark, compare configs, merge an improvement |

Rules that follow:
- **Two entry points, one data set.** The same snapshot and files feed both; nothing is entered twice, and every number links to the runs behind it.
- **Each first screen answers its user's question without a click.** The product engineer never scrolls past metrics to find a pending decision; the factory engineer never opens missions one by one to see a trend.
- **Crossing over is one click, in context.** A failed round in a ticket links to the pattern it belongs to; a pattern links to the runs and tickets that show it.
- **The same person wears both hats,** often in one day (today, the user is both): the switch is a top-level toggle, remembered per viewer, not a separate tool.

### 5. Factory engineering views (from Warp Factories' interface)

The user's look at Warp Factories (October 2026) shows a second audience for the page: not the person following a mission, but the person tuning the factory. Its navigation is the map:

- **Across factories:** an **Inbox** (every human action waiting, whatever the factory: our needs-you across missions and repos), **Runs** (every agent run, searchable), connected tools and **Secrets** (names only).
- **Per factory** (one per product surface; for us, one per repo or project): **Dashboard**, **Agents** (each role with its effective model, thinking level and brief), **Automations** (what starts work: P4's triggers), **Scorers** (P14's dimensions and their trend), **Self-improvement** (P15's open patterns, with a count badge), **Benchmarks** (suites, their tasks, past runs, a Run button), **Factory definition** (the versioned configuration, P11's manifest), **Settings**.
- **A benchmark page** describes its suite in one paragraph (tasks distilled from real runs, how many easy, medium, hard and extra-hard, which areas, which agent type it exercises) and has two tabs: **Runs** (configs compared) and **Tasks**.

For us, v2 of the cockpit adds, next to leads → mission → ticket: an Inbox across repos, Agents (from `effective-models.mjs`), Scorers and Benchmarks (from P14's files), Self-improvement (from P15's `patterns.md`) and the factory definition with its version. Still read-only; the Run and approve buttons wait for P12 or P6.

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
5. The zoom: leads → mission → ticket → verdict → log → diff, with keys; the phone shows Needs you. **M**

## Open questions

- SQLite (Atelier, SSSF) or JSONL? Proposed: JSONL in the mission folder, committed with the rest; SQLite only if the page gets slow.
- Should the page ever write? Proposed: no in this proposal. Decisions stay in `/factory-decide`; P6 adds buttons that call the same scripts.
- One page per mission or per repo? Proposed: per repo, missions as tabs, since a repo rarely runs more than one.
