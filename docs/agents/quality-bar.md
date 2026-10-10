# Quality bar

The code base is the fuel the team uses to bring value to customers. Every mission must leave it **safe, understandable by any human, battle-tested and predictable**. The code steward (G5) judges each mission's diff against this file. It is **repo-owned**: `install-into.sh` creates it once, then it is yours to sharpen. Keep the IDs stable; verdicts cite them.

Each item is checked on the **mission's diff**, not the whole repo. Pre-existing debt is not the mission's fault. The ratchet (`.factory/health-baseline.json`) only forbids making it worse.

## Safe

- **QB-SAFE-01** Every input from outside the process (user, API, file, env, queue) is validated or parsed into a typed value before use.
- **QB-SAFE-02** Errors are explicit: no swallowed exceptions, no empty `catch`, no failure turned into a default value without a log line saying so.
- **QB-SAFE-03** No secret, token, credential or personal data in code, logs, tests or fixtures.
- **QB-SAFE-04** Destructive or irreversible actions (delete, overwrite, send, pay) are guarded: dry-run, limit, confirmation, or idempotency key, as the spec decided.

## Understandable

- **QB-CLEAR-01** Clarity over cleverness: a reader new to the repo understands each function from its name, its signature and its body, without tracing elsewhere.
- **QB-CLEAR-02** Names come from `GLOSSARY.md`; one concept, one name, everywhere.
- **QB-CLEAR-03** Small units: a function does one thing; deep nesting, long parameter lists and boolean flag arguments are split.
- **QB-CLEAR-04** No hidden control flow: no magic values, no side effects in getters or constructors, no global mutable state added.
- **QB-CLEAR-05** No dead code, commented-out code, or speculative abstraction ("in case we need it").
- **QB-CLEAR-06** No logic duplicated from elsewhere in the repo; reuse or extract.

## Battle-tested

- **QB-TEST-01** Every failure path the spec names has a test, not only the happy path.
- **QB-TEST-02** Tests read like the spec: one behavior per test, named after it, expected values from the contract.
- **QB-TEST-03** Tests are deterministic: no sleeps, no real network, no wall-clock or random input without a seed.
- **QB-TEST-04** No test was deleted, skipped or weakened to make the mission pass.

## Predictable

- **QB-PRED-01** Every call that can hang has a timeout; every loop or batch over external data has a limit.
- **QB-PRED-02** Operations that can be retried are idempotent, or say why not.
- **QB-PRED-03** Configuration is explicit and documented; no behavior changes from undeclared environment variables.
- **QB-PRED-04** New dependencies are justified in the ticket or a decision, pinned, and maintained.

## The "explain it" test

For every changed source file, the steward writes three plain sentences: what it is for, how it works, what can go wrong. If it can't, a human won't either: that is a QB-CLEAR-01 finding.
