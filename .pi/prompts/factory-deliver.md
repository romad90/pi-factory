---
description: Record a ticket you built by hand (a path reserved for people, such as CI); its commit becomes the ticket's integration and goes to review
---
Arguments: the mission name, the ticket, optionally a commit (default: the last commit), then what the human did: `$@`.
The human has already made the ticket's change and committed it. Run this, with the mission, the ticket, the commit if given, and everything after them copied verbatim between the two marker lines (backticks, quotes and $ included; the quoted marker keeps them as text):

```
scripts/factory/human.sh deliver <mission> <ticket> [<commit>] --stdin <<'FACTORY_TEXT_END'
<what the human did, verbatim>
FACTORY_TEXT_END
```

Show its output. Then continue as the lead with the /factory loop for that mission (start at `scripts/factory/next.sh <mission>`). Never make the change yourself, and never send the ticket to a worker: the patch guard reserves its files for people.
