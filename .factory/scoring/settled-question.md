# Asked a question already settled

**Roles:** factory-worker, factory-worker-heavy, factory-reviewer, factory-review-axis, factory-validator
**Sample:** 0.5

## Look for
A question to the human (or a stop waiting for one) whose answer is already in the mission's `decisions.tsv`, the spec, the contract, or the ticket.

## Pass
The run asked nothing, or asked something no file answers.

## Fail
The run asked "should I mock the database?" while `decisions.tsv` already says "mock config/mongo".
