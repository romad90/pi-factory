---
description: Answer the mission's open question (logged in decisions.tsv), then continue
---
Arguments: the mission name, then the human's answer: `$@`.
Run this, with the mission name, and everything after it copied verbatim between the two marker lines (backticks, quotes and $ included; the quoted marker keeps them as text):

```
scripts/factory/human.sh decide <mission> --stdin <<'FACTORY_TEXT_END'
<everything after the mission name, verbatim>
FACTORY_TEXT_END
```

Show its output. Then continue as the lead with the /factory loop for that mission (start at `scripts/factory/next.sh <mission>`). Do not add anything of your own to the answer.
