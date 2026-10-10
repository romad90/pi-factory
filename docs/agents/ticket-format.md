# Ticket format

Tickets live in `.scratch/<feature>/issues/NN-<slug>.md`, numbered in build order. Written by the ticket writer (or by hand), approved by a human with `/factory-approve <feature> tickets`. `coverage.sh` (G2) checks them.

```markdown
# NN <title in the GLOSSARY's words>
**Size:** S | M | L

<What to build, in two to five sentences. Behavior, not implementation.>

## Covers
VAL-AREA-001, VAL-AREA-002

## Blocked by
01, 03

## Notes
<Decisions from decisions.tsv that apply; files likely involved.>
```

Rules:

- **`## Covers`** lists the assertion IDs the ticket makes true, or `## Covers: enabler` followed by one sentence naming what it unblocks. Every active assertion is covered by at least one ticket.
- **Size:** S = one unit and its tests; M = a few units, one seam; L = core logic or more than two assertions of core behavior. The efficient worker builds S and M; **L goes straight to the heavy worker**. Prefer splitting an L into two Ms.
- **`## Blocked by`** uses two-digit ticket numbers. No cycles.
- **Fix tickets** are named `NN-fix-<slug>.md` and cover the assertions (or `QB-` items) their finding names: one ticket per root cause, never one per failed case.
