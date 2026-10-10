---
name: contract
description: Write or amend the validation contract of a spec, the numbered, observable assertions that define done before any ticket exists. Use after /to-spec and before /to-tickets, or with "amend" when a critic, worker or validator shows an assertion is wrong.
---

# Contract

The contract defines done independently of any implementation. Workers take their expected values from it, and validators judge against it.

Read first: the mission's `spec.md`, `GLOSSARY.md`, `docs/agents/contract-format.md`, and the domain checklist `docs/agents/contract-checklist-<domain>.md`.

## Write

1. Append a `## Validation contract` section at the end of `spec.md`, in the format of `contract-format.md`.
2. Map every spec requirement to at least one assertion. For a requirement that can't be observed from outside, add it under `### Not covered` with the reason.
3. Walk the domain checklist. For each item, write an assertion or add it under `### Not covered` with the reason.
4. Size the contract to the feature. A small feature usually needs 2 to 5 assertions.
5. Write every `Then` as what an outside observer sees, in GLOSSARY.md terms.
6. Present the assertions as a numbered list and stop. The next step is `/contract-critic` in a fresh session. The human adds the approval marker at G1.

## Amend

Use when a critique finding, an escalation, or a verdict shows the contract is wrong.

1. Edit the assertion in place and keep its ID. Add `- **Amended:** <date>, <reason>`.
2. To drop an assertion, rewrite its heading as `### ~~VAL-…~~: <title>` and add `- **Withdrawn:** <date>, <reason>`.
3. New assertions take the next free number in their area.
4. Replace the approval line with `**Contract approved:** pending re-approval (amended <date>)`. The gate stays closed until the human approves again.
5. List the tickets whose `## Covers` cite a changed or withdrawn ID, so they can be updated.
