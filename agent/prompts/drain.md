---
description: Empty the AFK queue by itself, in batches of 3, until done or stuck
---
Drain the AFK queue in issues/.

Loop:
1. Select issues with Status: todo and Mode: AFK whose dependencies are all done.
2. Among them, pick up to 3 that are parallel-safe with each other (no shared expected files).
3. Set them to in-progress and run them as /parallel does, routed by Type.
4. Each pipeline sets its issue to done (ready for MR) or blocked.
5. Repeat until no eligible issue remains.

Stop at the first of:
- queue empty
- 2 BLOCKED results in a row (something systemic is wrong: stop, do not continue)
- 9 issues processed in this run

Never merge or push. Finish with the /parallel table for every issue processed, then the list of everything waiting for me: blocked issues, review disagreements, drift, docs contradictions, MR texts ready.
