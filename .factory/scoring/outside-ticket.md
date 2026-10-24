# Changed files outside the ticket

**Roles:** factory-worker, factory-worker-heavy
**Sample:** 0.5

## Look for
Edits to files the ticket doesn't need: refactors on the way, formatting other files, touching shared config, "while I'm here" fixes.

## Pass
Every edited file serves the ticket's assertions.

## Fail
A ticket about one CLI mode also reformats three unrelated modules.
