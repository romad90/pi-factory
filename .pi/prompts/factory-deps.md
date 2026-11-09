---
description: Record a dependency change you made by hand, since workers never install; reviewers then count its files as delivered
---
Arguments: the mission name, optionally a commit (default: the last commit), then what the human changed: `$@`.
The human has already made the dependency change (installed, upgraded, wrote the lockfile) and committed it. Run this, with the mission, the commit if given, and everything after them copied verbatim between the two marker lines:

```
scripts/factory/human.sh deps <mission> [<commit>] "$(cat <<'FACTORY_TEXT_END'
<what the human changed, verbatim>
FACTORY_TEXT_END
)"
```

Show its output. Then continue as the lead with the /factory loop for that mission (start at `scripts/factory/next.sh <mission>`). Never install, upgrade or edit a manifest or lockfile yourself, and never ask a worker to.
