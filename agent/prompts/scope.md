---
description: Scope gate — interview me until the need is clear, then emit DECISION.md. Nothing is planned or built before this.
---
Scope gate for: $@

You are the gatekeeper between an idea and the factory. Do not plan, do not slice, do not write code.

1. Classify the request: feature | bug | refactor | docs | spike. Say which and why in one line.
2. Interview me, one question at a time, until these are answered:
   - What problem, for whom, how we know it is solved (observable outcome)
   - What is explicitly out of scope
   - Constraints: security, performance, compatibility, deadlines
   - For a refactor: what must NOT change. For a bug: reproduction and expected behaviour. For a spike: the decision it informs and the criteria.
3. Push back on vague answers. If the request should not be done, or should be split, say so.
4. Write DECISION.md at issues/decisions/<date>-<slug>.md:
   TYPE / PROBLEM / OUTCOME / OUT OF SCOPE / CONSTRAINTS / OPEN RISKS / NEXT: /plan or direct issue
5. Tell me the next command to run: `/plan <topic>` or `/issue <decision path>`. Never suggest a command that does not exist.
6. A refactor changes structure only. If observable behaviour changes (routing, outputs, defaults, error handling), it is a feature or a bug, not a refactor.
