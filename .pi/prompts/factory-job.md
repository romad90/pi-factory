---
description: "Give the factory a job in one line: it measures the code, the architect proposes a strategy, you approve it once, the missions run"
---
Arguments: `$@` (a name for the job in lowercase words and dashes, then what you want, in one line).
Run `scripts/factory/human.sh job $@`. Show its output. If it succeeded, continue as the lead with the /factory loop for `$1` (start at `scripts/factory/next.sh $1`).
