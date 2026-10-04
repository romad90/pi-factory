---
description: HITL planning loop — scout, grill, PRD, then slice into typed AFK/HITL issues
---
We are planning: $@

If a DECISION.md exists for this topic in issues/decisions/, read it first and treat it as the contract. Do not write production code.

1. Run the `scout` subagent on the topic and read its report. For large or legacy areas, also run `architect`.
2. Grill me using the grill-with-docs skill (fall back to grill-me). One question at a time, until every branch of the decision tree is resolved.
3. Write the PRD with the to-prd skill, into issues/prd-<slug>.md.
4. Slice it with the to-issues skill into issues/<NNN>-<slug>.md, using issues/TEMPLATE.md. Every issue gets a Type: feature | bug | refactor | docs | spike.

Slicing rules (these make parallel work possible):
- Each issue is a thin vertical slice, demoable on its own.
- Refactors are separate issues from features. Never mix a structure change and a behaviour change in one issue.
- Every new issue starts with Status: todo. Tag each issue AFK or HITL. AFK only if acceptance criteria are testable, a verification command exists, and no design decision remains.
- List expected files per issue. Any shared file means NOT parallel-safe. No exceptions, no caveats in prose: if you would write "except", the answer is no.
- Pipeline and deployment definitions (.gitlab-ci.yml, CI includes, Dockerfiles, anything that triggers a deploy) are always HITL. Config such as Helm values may be AFK only if a local, offline verification exists (e.g. helm lint / helm template per environment) and nothing is deployed.
- End with a table: issue — type — AFK/HITL — depends on — parallel-safe with.
5. Before finishing, re-check every issue against these rules and fix the files themselves (Mode, Parallel-safe with), not just the table.
6. Finish by telling me the run command: `/tw23-drain`, `/tw23-parallel <issues>`, or the pipeline matching each AFK issue's Type. Never suggest `/tw23-issue` (issues already exist) or a command that does not exist.
