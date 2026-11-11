---
description: Send an integrated ticket back to review, not to build (its code stands; the review must run again)
---
Arguments: the mission name, the ticket, then the human's reason: `$@`.
Run this, with the mission and the ticket, and everything after the ticket copied verbatim between the two marker lines (backticks, quotes and $ included; the quoted marker keeps them as text):

```
scripts/factory/reset-ticket.sh <mission> <ticket> --review --stdin <<'FACTORY_TEXT_END'
<everything after the ticket, verbatim>
FACTORY_TEXT_END
```

Show its output. Then continue as the lead with the /factory loop for that mission (start at `scripts/factory/next.sh <mission>`). Do not add anything of your own to the reason.
