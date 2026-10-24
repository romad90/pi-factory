# Wrote redundant tests

**Roles:** factory-worker, factory-worker-heavy
**Sample:** 0.3

## Look for
New tests that repeat existing ones, test the same behavior several ways, or assert implementation details nobody asked for. Tests cost tokens to write and minutes to run forever.

## Pass
Each new test pins one behavior the ticket or its assertions name, not already pinned elsewhere.

## Fail
Five tests that each check a different field of the same response, where one assertion on the whole response would do; or a copy of an existing test with a new name.
