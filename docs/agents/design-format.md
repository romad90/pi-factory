# Program design format

Lives at `.scratch/<feature>/design.md`. Written by the designer after the contract is approved (G1) and before any ticket; approved by a human with `/factory-approve <feature> design` (G1b). Feature and refactor missions get one; others only when the spec says `**Design:** yes` (`**Design:** no` skips it).

The design is the shape of the code, not the code: every decision here is one the reviewer would otherwise make in code review, the most expensive moment to change your mind (D94). Keep it short enough to read in ten minutes.

```markdown
# Design: <mission>
**Design approved:** <date> — by <name>        (written by /factory-approve, never by the designer)

## Call stacks
```diff
 entrypoint
   runCommand
+    handleCreateResource          # VAL-RES-001
+      ResourceClient.create(input)
+        POST /resources
-    legacyCreateFlow              # removed: VAL-RES-003
```

## Files
```diff
 src/resource/
+├── resource-client.ts      # NEW: wraps the API calls (VAL-RES-001)
~└── resource-route.ts       # MODIFIED: wires create into the route
```

## Types and signatures
```ts
create(input: CreateInput): Promise<Resource>   // VAL-RES-001, VAL-RES-002
```

## Structure (refactor only)
Before → after, one line per module that moves, splits or merges, with the AGENTS.md rule or spec line it serves.

## Slices
1. <thinnest end-to-end path, observable how> — VAL-RES-001
2. <widening> — VAL-RES-002

## Not placed
- <assertion>: <why>
```

Rules:

- Diffs show what changes against today's code: `+` new, `-` removed, `~` modified, plain lines for context. Read the code first; a design against code you didn't read is a guess.
- Every item names the assertion IDs it serves. An item that serves none is speculative: drop it.
- No implementation bodies, no tests. Signatures, not functions.
- `## Slices` orders the work as vertical slices (ticket-format.md): the ticket writer turns each slice into one or more tickets.
- After approval, the design is the reference for the reviewer's Spec axis: a ticket that departs from it says why in its report, or the reviewer flags it.
