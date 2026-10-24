# Read far more than the ticket needed

**Roles:** factory-worker, factory-worker-heavy, factory-reviewer, factory-review-axis
**Sample:** 0.3

## Look for
Reading whole directories, large generated files, lockfiles, or the same file repeatedly; listing the repo again and again; output far larger than the task. Context spent on reading is context not available for reasoning.

## Pass
Reads are targeted: the ticket's files, their tests, and what they call.

## Fail
The run read `package-lock.json` and every file under `src/` for a ticket that touches one module.
