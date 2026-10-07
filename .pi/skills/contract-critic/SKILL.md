---
name: contract-critic
description: Attack a validation contract before the human approves it. Find missing failure paths, Then lines that can't be observed, ambiguous wording, and spec requirements with no assertion. Use after /contract, in a fresh session, on a different model than the one that wrote the contract.
---

# Contract critic

The contract is the highest-leverage artifact in a mission: a wrong one makes every later step converge confidently on the wrong result. Your job is to break it before the human approves it.

Read: the mission's `spec.md` (requirements and contract), `GLOSSARY.md`, `docs/agents/contract-format.md`, `docs/agents/contract-checklist-<domain>.md`.

Write `contract-critique.md` in the mission directory:

```markdown
# Contract critique: <feature>
**Critique result:** CLEAN | FINDINGS

## Traceability: spec → contract
| Spec requirement | Assertions | Status |
|---|---|---|
| <requirement> | VAL-… | covered / partial / missing / not covered (reason given) |

## Checklist
| Item | Assertions | Status |
|---|---|---|

## Findings
- [blocking] VAL-ROUTE-002: <problem>. Suggested fix: <fix>
- [non-blocking] <problem>. Suggested fix: <fix>
```

What counts as a finding:

- **[blocking]:** a requirement with no assertion and no "not covered" reason; a `Then` that can't be observed from outside; an assertion two readers would judge differently; a checklist item missing with no reason; two assertions that contradict each other.
- **[non-blocking]:** unclear wording that still has one reasonable reading; a weak `Evidence` line; a GLOSSARY term used loosely.

Report findings only. The author applies changes with `/contract amend`, and the human decides at G1.
