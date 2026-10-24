---
description: "Approve in one word: the contract (G1), the design (/factory-approve <mission> design, G1b), the proposed tickets (/factory-approve <mission> tickets), or an investigation's conclusion (/factory-approve <mission> conclusion), then continue"
---
Arguments: `$@` (the mission, optionally followed by `design`, `tickets` or `conclusion`).
Run `scripts/factory/human.sh approve $@`. Show its output. If it succeeded, continue as the lead with the /factory loop for mission `$1` (start at `scripts/factory/next.sh $1`).
