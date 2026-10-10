# Quality bar: HTTP APIs

Extra items for the code steward (G5), on top of `quality-bar.md`. Judged on the mission's diff.

- **QB-API-01** Errors are built by one shared module into the single error shape; no handler writes an ad-hoc error body.
- **QB-API-02** Requests are parsed and validated at the edge into typed values; handlers never read raw input deeper in.
- **QB-API-03** Idempotency keys are stored and checked in the same transaction as the effect they protect.
- **QB-API-04** Every list is bounded (maximum `limit` enforced in code) with a stable sort that includes a unique tie-breaker.
- **QB-API-05** No existing response field, type or status code changed or removed without a new version.
- **QB-API-06** The request ID is propagated to logs and to outbound calls.
- **QB-API-07** Outbound calls have timeouts; automatic retries only on idempotent operations, with backoff.
- **QB-API-08** Money in integer minor units with currency; time in UTC; no floats for amounts.
- **QB-API-09** Webhook signatures are verified with a constant-time comparison and a replay window (Public APIs).
