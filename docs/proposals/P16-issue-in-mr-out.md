# P16. Issue in, MR out: the factory works where the team already looks

**Status:** draft, after mission 4 · **Effort:** M · **Depends on:** P2 (the scripted lead, D91); P6 hosts it later, P12 keeps it running

## Problem

Warp Factories (October 2026) sells one experience: "issues, tickets and Slack messages in, reviewed pull requests out; agents do the work, people approve specs and merges". Its three human gates are ours: approve the spec, answer questions, merge. The difference is where it happens:

| What a teammate needs | Warp | Us today |
|---|---|---|
| Start work | Mention the factory in an issue, a Slack thread, a ticket | Write a spec and type `/factory` on the machine that runs it |
| See where it is | The thread where the request started, the factory inbox | `next.sh` or the cockpit, on that same machine |
| Approve, answer | From the inbox or the thread | `human.sh` in that machine's terminal |
| Find the result | A PR linked from the request | An MR opened by `mr.sh` |

So the factory is visible to one person. The pilot's own criterion, "activity visible in GitLab", is not met by the process itself, only by the MRs at the end.

Warp's figures are the vendor's and their review verdict is only advisory; ours are gates in code. We don't want their product, hosted compute or an LLM foreman. We want the experience: a teammate sees and drives the factory from the forge.

## Proposal

The forge issue becomes the mission's front door and its status page. Same loop, same files; a thin layer of scripts reads and writes the issue.

### 1. A label starts a mission

`factory:feature`, `factory:bugfix`, `factory:maintenance`, `factory:refactor` (P6's label table, without the director). `intake.sh` (on a schedule, or run by hand) lists open issues with a factory label and no mission yet, and for each:

- creates `.scratch/<mission>/` with the issue's text as the request, its URL and its author;
- comments on the issue: the mission name, the branch, and what happens next ("grilling: I will ask questions here").

The spec is still the human's (the cheat sheet's first rule: the spec decides what value is): either the issue already holds a spec in our format, or the first step is a grilling done as comments on the issue, and `/to-spec` writes the spec from that thread.

### 2. The factory comments at every gate, and only there

`run.sh` already stops at each human step with a `NEXT` line. At each stop, `notify.sh` posts one comment, from the factory's own account:

- the contract (G1), the design (G1b), the tickets: a link to the file on the branch, the critic's summary, and what to reply;
- a question: the question, the ticket, and the answer format;
- the MR: its link, the metrics (rounds, human decisions, cost), Known limits.

No comment per round, no progress spam: the cockpit and `metrics.sh` are for that. A comment says "you are needed", or "done".

### 3. Approvals and answers come back from the issue

A reply on the issue is read by `intake.sh` and turned into the `human.sh` call it stands for: `/approve`, `/approve design`, `/approve tickets`, `/decide <answer, and why>`, `/amend <change>`, `/accept-unverified <ids> <why>`.

It counts only when **its author is a human listed in `.factory/approvers`** and not the factory's account. That closes D101's open hole: today the lead can run `human.sh approve` itself, and only the decision log shows who did. With approvals coming from the forge, the author is checked by the forge's identity, not by the factory. `decisions.tsv` records the comment's URL as evidence.

### 4. The inbox, per person

The cockpit's first screen for a product engineer (P10 §5) becomes "what waits on me": every mission stopped at a human step whose issue names me as author, assignee or reviewer, across repos, with the link to the comment to answer. The forge's own notifications do the rest: a comment that needs you reaches you by mail or phone without anything new to install.

### 5. Later: the run keeps going without a laptop

With P12 (Pi Durable) on a shared machine, the loop resumes when an approval comment arrives, at night included. Until then, `intake.sh` runs on the machine that runs the missions, and a closed laptop pauses the factory as it does today.

## What it does not do

- It does not merge. The MR is opened by `mr.sh` and merged by a human, under the target branch's protection.
- It does not change the gates, the guards or the files: the issue is a window on `.scratch/`, never a second source of truth. A mission can still be run entirely from the terminal.
- No Slack, no Teams, no web app in this proposal. They come only if the pilot's numbers ask for them.

## Trade-offs

| For | Against |
|---|---|
| The team sees and drives the factory where it already works; the pilot's visibility criterion is met by the process | The factory needs its own forge account and token, scoped to the project: comment and read issues, push branches, open MRs, nothing else |
| Approvals checked by the forge's identity close D101's self-approval hole | Comments are untrusted input: `intake.sh` parses commands only, from listed authors, and passes text through `--stdin` (D68), never into a prompt as instructions |
| Every mission has a public trail: request, questions, answers, MR | A noisy factory is ignored: one comment per human step, never per round |
| No new UI to build or host | Polling a forge on a schedule; webhooks only with P6 |

## Plan

1. Labels, `intake.sh` (issue → mission folder, first comment), `.factory/approvers`. **S**
2. `notify.sh` called by `run.sh` at every human stop; comment templates per STEP. **S**
3. Replies → `human.sh`, author checks, comment URL in `decisions.tsv`; tests with a fake forge. **M**
4. The cockpit's per-person inbox (P10 §5). **S**
5. On a shared runner with P12. **with P12**

## Open questions

- Which issues: any issue in the repo with a label, or only in a project the team sets aside for factory work? Proposed: the repo's own issues; a label is a deliberate act.
- Grilling as issue comments: does it work as well as the live `/grill-with-docs`? Try it on one mission; keep the live grilling as the default until then.
- Who is on `.factory/approvers`: the MR's reviewer named in the spec (D95), the issue's author, both? Proposed: the spec's reviewer and the team's leads.
- Also take a terminal-only approval path for missions without an issue: a one-time code `human.sh` prints and the human types, which the agents' environment never sees.

## What it borrows

- Warp Factories: work items keep their source from intake to handoff, results go back to the thread they came from, an inbox of what needs a person, three human gates.
- OpenAI's Symphony: the issue tracker as the control plane (ideas.md, October scan).
- P6: labels decide the lane; one door in.
