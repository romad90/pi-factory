# Contract checklist: batch jobs and batch bots

For the contract author and critic. Mission 1 used a conversational-bot checklist on a batch bot and produced noise; this is the batch version.

- **Exit codes.** Each outcome has a distinct, documented code (e.g. 0 done, 1 partial, 2 configuration, 3 dependency, 4 unexpected), asserted per scenario.
- **Counts add up.** The run summary satisfies `processed = succeeded + failed + deferred`, and every status is counted the same way in every assertion.
- **Partial failure.** What happens to item N+1 when item N fails, per failure class: a client error on one item (continue), an upstream 5xx or timeout (stop, report the rest as deferred), a conflict that means "already done" (count as succeeded).
- **Safe re-run.** Running twice in a row changes nothing the second time; an interrupted run can be restarted.
- **Caps.** A maximum number of items per run, enforced, with what happens to the rest.
- **Throttling.** A rate toward each dependency, configurable.
- **Dry-run.** A mode that does everything except the effect, and says so in its output; the default for a first deploy is stated.
- **No overlap.** Two scheduled runs never act at the same time (lock or schedule guarantee).
- **Audit.** Each effect leaves one event or log line with the item ID and the outcome.
- **Configuration.** Missing or invalid configuration fails fast with the configuration exit code, before any effect.
- **Observability.** A summary line per run (counts, duration, exit code) that an alert can read.
