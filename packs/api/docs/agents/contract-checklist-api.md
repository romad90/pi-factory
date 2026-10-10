# Contract checklist: HTTP APIs

For the contract author and critic. Each item is something the contract should assert, for every endpoint the mission adds or changes. **Always** applies to any API; **Public** only when third parties integrate with it. Inspired by Stripe's API conventions; prune what doesn't fit, keep it consistent with the existing API.

## Always

- **Errors.** Each error path returns the documented status and the single error shape: `{ "error": { "type", "code", "message", "param"?, "request_id" } }`. Validation errors name the offending `param`. 4xx means the caller can fix it; 5xx never leaks internals.
- **Authentication and authorization.** Unauthenticated → 401, authenticated but not allowed → 403, someone else's resource → 404 (no existence leak). No credential in a URL.
- **Idempotency.** Every POST that creates something or triggers an effect accepts an `Idempotency-Key`: same key and same body → same response, effect done once; same key, different body → 409 (or 422) with a clear `code`. The retention window is stated.
- **Lists.** Cursor pagination (`limit`, `starting_after`/`ending_before` or an opaque cursor), a maximum `limit`, a stable order, `has_more`. Never an unbounded list.
- **Request IDs.** Every response carries a request ID (header and error body); the same ID is in the logs.
- **Rate limits.** Over the limit → 429 with `Retry-After`.
- **Compatibility.** Changes are additive: no removed or renamed field, no changed type or status code on an existing endpoint. Anything else needs a new version.
- **Data types.** Money as integer minor units plus currency; timestamps in UTC, one format; IDs as opaque strings (prefixed by type helps: `cus_…`); enums as lowercase snake_case strings.
- **Timeouts.** Calls to dependencies time out; the API's own behavior on a dependency timeout is asserted (status, `code`, retryable or not).

## Public

- **Versioning.** The version is explicit per request (header) and pinned per client by default; a breaking change ships only as a new version with a changelog entry.
- **Webhooks.** Signed (HMAC over timestamp + body, replay window), delivered at least once with retries and backoff, each event with a unique ID so receivers can deduplicate.
- **Expansion.** Related objects returned as IDs, expandable on request (`expand[]`), so responses stay small and predictable.
- **Documentation.** Every new field, error `code` and endpoint appears in the reference docs in the same MR.
