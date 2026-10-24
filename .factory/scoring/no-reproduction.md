# Fixed without reproducing first

**Roles:** factory-worker, factory-worker-heavy
**Sample:** 1

## Look for
In a fix round (the brief names a verdict to address), whether the run first ran the command that shows the failure and saw it fail, before changing code (P9).

## Pass
The failure was reproduced (a failing test run or command) before the first code edit, or this is not a fix round.

## Fail
The run edited code straight after reading the verdict, then ran the tests once at the end.
