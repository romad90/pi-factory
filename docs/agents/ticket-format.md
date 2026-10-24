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

- **Vertical slices** (D95): each ticket delivers something that runs and can be observed end to end (a command that answers, a request that returns, a test of the public entry point that goes green), not one layer of the stack. Thinnest path first, then widen: one happy path through every layer, then the next case, then the errors. Never "all migrations, then all services, then the API": nothing can be checked until the last ticket, and a wrong turn is found at the end. A ticket whose result can't be observed on its own is merged with its neighbour. When the mission has a design (`design.md`), its `## Slices` give the order.
- **`## Covers`** lists the assertion IDs the ticket makes true, or `## Covers: enabler` followed by one sentence naming what it unblocks. Every active assertion is covered by at least one ticket.
- **Size:** S = one unit and its tests; M = a few units, one seam; L = core logic or more than two assertions of core behavior. The efficient worker builds S and M; **L goes straight to the heavy worker**. Prefer splitting an L into two Ms.
- **`## Blocked by`** uses two-digit ticket numbers. No cycles. Tickets that could run in one wave never change the same file: give each its own file, or chain them with `Blocked by` (in mission 3, four tickets writing one test file conflicted on integration).
- **Fix tickets** are named `NN-fix-<slug>.md` and cover the assertions (or `QB-` items) their finding names: one ticket per root cause, never one per failed case.
- **Notes after an escalation:** when several tickets escalate on the same mistakes, the human adds a `## Notes from rounds 1-3` section (the pitfalls, and the passing tickets to copy) and resets them. In mission 2 one such note unblocked five tickets.

**Characterization missions** (tests that pin existing behavior, production code frozen):

- A constraint of the mission is not a test. "`src/` is unchanged" is enforced by the patch guard and shown as evidence in the MR (`git diff <base> -- src/` empty); a test asserting it fails for everyone who later edits `src/`, starting with the refactoring the mission prepares.
- A test that expects a connection error sets a short timeout (for MongoDB, `serverSelectionTimeoutMS` in the URI the test passes), or it waits out the driver's default (30 s) on every `npm test`.
- Values the code reads at load time (required environment variables, config lists) come from the code under test, not from a copy in each test file: copies go stale when production adds one.
- When an assertion's Given makes its Then unreachable, the test pins the actual behavior, says so in its name, and the worker reports `CONTRACT DOUBT:`. One amendment at the end covers them all.
