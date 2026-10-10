---
description: Approve in one word: the contract (G1), or the proposed tickets (/factory-approve <mission> tickets), then continue
---
Arguments: `$@` (the mission, optionally followed by `tickets`).
Run `scripts/factory/human.sh approve $@`. Show its output. If it succeeded, continue as the lead with the /factory loop for mission `$1` (start at `scripts/factory/next.sh $1`).
