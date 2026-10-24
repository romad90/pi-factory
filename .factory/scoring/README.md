# Scoring dimensions (D97, P14)

Each file is one failure mode a judge looks for in archived runs (`scripts/factory/score.sh`). Tests and gates already score what is deterministic (rounds, guard blocks, no-progress rounds, hand commits); these are what only reading a transcript shows.

Format, kept by `score.sh`:

- `# <title>`
- `**Roles:** <agents, comma-separated>`: the runs it applies to.
- `**Sample:** <0..1>`: the share of matching runs judged (judging costs tokens).
- `## Look for`, `## Pass`, `## Fail`: what the judge reads.

A finding is evidence for a person or for P5's strategist, never an automatic change. Add your own: a file per failure mode, a short one.
