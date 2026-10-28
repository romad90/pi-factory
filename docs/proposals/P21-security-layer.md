# P21. Security layer: a scanner gate in code, then a security axis that reads what the scanner can't

**Status:** proposed, after mission 5 · **Effort:** M · **Depends on:** D62 (lint ratchet, the same pattern), P20 (token budget: the axis reads the diff and the scanner's findings, not the spec)

## Problem

No part of the factory looks for vulnerabilities on purpose. What exists:

| Where | What it checks | Security content |
|---|---|---|
| Reviewer (code-review skill) | Spec axis, Standards axis (repo rules, Fowler smells) | none |
| Code steward (quality bar) | the mission's diff | QB-SAFE-01 inputs validated or parsed into typed values; QB-SAFE-03 no secrets or personal data; QB-SAFE-04 destructive actions guarded |
| Patch guard (code) | every worker patch | secret-shaped strings; silenced checks; factory, CI and hook edits |

No agent is asked whether the change can be exploited. Nobody traces untrusted input to a query, a command, a file path or an HTML page; nobody checks authorization (can user A reach B's data), server-side request forgery, path traversal, unsafe deserialization or weak crypto; no scanner runs, and dependencies are not audited. The fix missions queued on mission 4's and 5's projects touch exactly this: outside calls with no timeout, static files served from a source path, a service with seven critical gaps.

Anthropic's own process (How the Claude Code team does code review, October 2026) keeps security as a separate layer whose open findings block the merge, next to the bug review. That is the benchmark.

## Design: the floor in code, the judgement in a model

1. **A scanner gate (SAST), in code.** Semgrep with its standard rule sets for the project's languages (injection, SSRF, path traversal, hardcoded secrets, insecure crypto), run on the mission's diff by `self-check.sh` and `gate.sh`, offline, with rules vendored and pinned like the skills (hash-checked). A ratchet like the lint baseline (D62): the base's findings are recorded at onboarding (`.factory/security-baseline.txt`), and a mission may add none. `factory setup` rehearses the command like the others (D102), and proposes it when the language is supported.
2. **Dependencies, reported.** The ecosystem's audit (`npm audit --omit=dev --json`, `pip-audit`, `govulncheck`) runs at onboarding and at the MR: findings in dependencies the mission added or upgraded block; old ones become a finding for the owning team, never mission work (the P18 rule for vulnerabilities seen in install output).
3. **A security axis in the review**, for missions whose diff touches a boundary (input parsing, auth, outside calls, file system, queries, process execution: detected from the diff, not guessed). Fresh context, another family than the workers (D31). It reads the diff and the scanner's findings, nothing else (P20). It does what a scanner can't: trace each untrusted value from its source to its sinks across the diff, check authorization on every new path, and say for each scanner finding whether it is real. Its `[blocking]` findings block like any verdict; a dismissed scanner finding needs a reason the human sees.
4. **Security assertions in the contract.** When a spec's stories touch a boundary, the contract author adds assertions for it (`VAL-SEC-…`: rejected input, refused access, a bounded outside call), so the validator checks them like any behavior, with a test as evidence.

## Why this order

A scanner is deterministic, cheap and the same every run, but it only knows the patterns its rules describe and can't judge intent: "this user must not see that record" is invisible to it. A model reasons about intent, but varies between runs and costs tokens. The scanner sets the floor everywhere; the model goes only where the diff crosses a boundary, and reads the scanner's output instead of rediscovering it.

## Outside checks

- A seeded benchmark: a handful of archived tickets with a known vulnerability planted in the diff (an injection, a path traversal, a missing ownership check, an outside call with no timeout). The gate and the axis must flag the planted flaw, and stay quiet on the clean versions of the same tickets: recall and false-alarm rate, measured on the bench (D98) before the layer gates anything.
- The scanner's findings on a real mission's diff, labelled by the human (real, false alarm, accepted risk): the false-alarm rate decides which rules stay.

## Not doing

- Blocking a mission on old findings in the base or in dependencies it didn't touch: they go to the owning team.
- A model reading the whole repository for vulnerabilities: that is an audit, a mission of its own (exploration intent), not a gate on every MR.
- Dynamic testing (DAST, fuzzing) in the gate: worth a proposal of its own once a project has a runnable environment the factory may start.
