---
description: "Record a dependency change you made by hand (/factory-deps <mission> [<sha>] <what changed>, e.g. /factory-deps get-port-7 get-port 5.1.1 to 7.1.0, lockfile by npm 10), since workers never install; reviewers then count its files as delivered"
---
Arguments: the mission name, optionally a commit (default: the last commit), then what the human changed: `$@`.
Form: `/factory-deps <mission> [<sha>] <what changed>`, for example `/factory-deps get-port-7 get-port 5.1.1 to 7.1.0, lockfile by npm 10`. What changed is required. If the arguments hold only a mission (and maybe a commit), don't run anything: ask the human what they changed, then run the command below with their answer.
The human has already made the dependency change (installed, upgraded, wrote the lockfile) and committed it. Run this, with the mission, the commit if given, and everything after them copied verbatim between the two marker lines (backticks, quotes and $ included; the quoted marker keeps them as text):

```
scripts/factory/human.sh deps <mission> [<commit>] --stdin <<'FACTORY_TEXT_END'
<what the human changed, verbatim>
FACTORY_TEXT_END
```

Show its output. Then continue as the lead with the /factory loop for that mission (start at `scripts/factory/next.sh <mission>`). Never install, upgrade or edit a manifest or lockfile yourself, and never ask a worker to.
