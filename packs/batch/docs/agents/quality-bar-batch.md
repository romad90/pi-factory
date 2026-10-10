# Quality bar: batch jobs

Extra items for the code steward (G5), on top of `quality-bar.md`.

- **QB-BATCH-01** The effect for one item is idempotent (a re-run or retry can't double it).
- **QB-BATCH-02** Every loop over external data is bounded by the configured cap.
- **QB-BATCH-03** Dry-run is checked at the single place the effect happens, not scattered.
- **QB-BATCH-04** Exit codes come from one mapping; no `exit` with a literal elsewhere.
- **QB-BATCH-05** The run summary is computed from the same counters the logic updates, never re-derived.
