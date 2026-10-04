---
description: Time-boxed research spike — evidence, comparison, ADR draft for me to decide
---
Run the spike for issue: $1

1. Read the issue. Stop if the question, the options, or the decision criteria are missing.
2. Run `scout` on the part of the codebase the question concerns.
3. Run `researcher` with the issue path and the scout report.
4. Run `reviewer-2` on the ADR draft with this instruction: challenge the recommendation, look for missing options and unverified claims.
5. Show me the recommendation, the challenge, and the ADR draft path. The decision is mine; do not mark the ADR as accepted.
6. Log one line to .factory/runs.jsonl (schema in ~/.agents/AGENTS.md) with "type":"spike".

At start, set the issue's Status to in-progress. At the end, set it to done (ready for MR) or blocked.
