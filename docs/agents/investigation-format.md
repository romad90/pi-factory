# Investigation format (D99)

For missions that list `## Context repos` with **Intent:** bugfix or exploration. The factory reads these files; keep the headings and field names exact.

## The explorers' briefs

`.scratch/<mission>/context/<repo>.md`, one per context repo, and `home.md` for this repo's side:

```markdown
# <repo>: <its role, one line>
**Commit:** <the commit read, from context.tsv>

## How it reaches the others
- calls `PUT /resources/:id` every 5 minutes (`src/sync/poll.ts:41`)

## Data
## Retries, timeouts, idempotency
## Ordering and ownership assumptions
## Configuration that changes behavior
## Not found
```

An answer to a question is `.scratch/<mission>/context/answers/Q<n>.md`: the question, the answer, the evidence.

## investigation.md

```markdown
# Investigation: <mission>

## System map
<who calls whom, in what order, with which data: a sequence diagram or a short list>

## Hypotheses
- **H1** supported: <claim> — <evidence: path:line, an answer Qn, a test run>
- **H2** ruled out: <claim> — <evidence>
- **H3** open: <claim> — <what would settle it>

## Questions
- Q1 [bot-sync-a]: <what only that repo can answer>
- Q2 [home]: <a question about this repo, answered by an explorer here>

## Conclusion
**Cause:** <one paragraph>
**Fix belongs:** here | <repo name from context.tsv>
**Reproduction:** issues/01-reproduce-<slug>.md

### Assertions for the fix
- <the behavior this repo must have toward its callers, e.g. a sync replayed twice creates no duplicate>
```

- Questions are asked in waves: each `investigate` round answers the open ones with fresh explorers, then the investigator updates this file. `FACTORY_INVESTIGATE_ROUNDS` (default 3) bounds the rounds.
- A human approves the conclusion: `/factory-approve <mission> conclusion` adds `**Conclusion approved:** <date>` under `## Conclusion`.
- Fix here (bugfix): the reproduction ticket comes first; once it is integrated, its `**Test:**` file is frozen (D93): later tickets fix the code, never that test.
- Fix elsewhere: `finding-for-<repo>.md` goes to that repo's team; the mission changes nothing here.
- Exploration: the approved investigation is the deliverable.
