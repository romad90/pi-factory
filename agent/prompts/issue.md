---
description: Turn a DECISION.md into one issue from the template, without /plan
---
Read the decision at $1, then write one issue at issues/<NNN>-<slug>.md using issues/TEMPLATE.md.
Copy Type, outcome, out of scope and constraints from the decision. Status: todo.
Set Mode to AFK only if acceptance criteria are testable, a verification command exists and no design decision remains; otherwise HITL. Pipeline and deployment definitions (.gitlab-ci.yml, Dockerfiles, deploy triggers) are always HITL.
Show me the issue and the pipeline command to run. Do not start it.
