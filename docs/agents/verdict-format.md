# Verdict format

Written by `/code-review` (per ticket), `/verify-behavior` (per mission) and light-lane reviews. Parsed by `scripts/factory/`; keep the bold field lines exact.

| Verdict | Path |
|---|---|
| Code, per ticket | `.scratch/<feature>/verdicts/<ticket-file-stem>-code.md` |
| Behavior, per mission | `.scratch/<feature>/verdicts/behavior.md` |
| Light lane | `.scratch/light/<slug>/verdicts/code.md` |

```markdown
# Verdict: <ticket stem | behavior | slug>
**Result:** PASS | FAIL
**Commit:** <full SHA reviewed or run against>
**Brief:** <the brief-id line from your task>

## Assertions
- VAL-ROUTE-001: PASS — <evidence: test name, log line, result file>
- VAL-ROUTE-002: FAIL — observed <x>, expected <y>
- VAL-ROUTE-003: UNVERIFIED — <why it could not be checked>

## Issues
- [blocking] <issue>
- [non-blocking] <issue>
- [suggestion] <issue>
- [amendment] VAL-…: <why the assertion itself looks wrong>
```

Rules:

- `PASS` means no `[blocking]` issue and every assertion in scope passes.
- **Evidence or label (D40).** Every assertion line is `PASS — <evidence>`, `FAIL — <what>`, or `UNVERIFIED — <why>`. A PASS without evidence counts as unverified. For behavior, unverified assertions block G4 until proven or accepted by a human (`/factory-accept-unverified`), and the MR lists them as Known limits.
- **Round and model are written by the factory (D38, D39).** `scripts/factory/collect.sh` numbers the round from the verdict history (`<stem>.r<N>.md`) and writes the model configured for the role. Whatever the agent wrote there is replaced. The gate rejects a verdict that wasn't recorded or was edited afterwards.
- `**Brief:**` copies the `brief-id:` line of the task. The gate recomputes it for the role, ticket and commit: a PASS without a matching id means the reviewer wasn't dispatched with a generated, file-paths-only brief (D32).
- Code verdicts review one integration commit (`.scratch/<feature>/state/<ticket>.integrated`); `**Commit:**` must equal it.
- `**Commit:**` is the commit the verdict was produced on. The gate rejects it if code changed afterwards (outside `.scratch/`).
- Every recorded FAIL is a round: review FAILs, failed integrations (`**Brief:** integrate`) and worker runs without a patch (`**Brief:** worker-no-patch`). At round 3 still failing, the ticket escalates. From round 2 the heavy worker builds it.
- Validators report. Each `[amendment]` goes to `/contract amend`.

## Behavior verdicts: clustered findings (D25)

The behavior verdict crosses the wall, so it carries **findings clustered by root cause**, never case contents or raw output (those stay in `instrument/results/`). Add this section:

```markdown
## Findings
### F1: <root cause, at feature or subsystem level>
- **Assertions:** VAL-ROUTE-002, VAL-CROSS-001
- **Weight:** <share of failing case weight>
- **Directive:** <what is missing or wrong, in behavior terms; no case inputs>
```

You (the orchestrator in phase 1) read the findings, reject noise, and turn each real one into **one** fix ticket (`NN-fix-<slug>.md`, `## Covers` = its assertions). One ticket per root cause, not per failed case.
