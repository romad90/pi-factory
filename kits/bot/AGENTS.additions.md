## Verification without side effects (bots)

Bots send messages, call external APIs and may act on real accounts. Agents must verify without touching anything real.

- Every external integration has a mock or dry-run mode, selected by `<ENV VAR / flag>`. Tests always use it.
- Test tokens and sandbox environments only. Live credentials never exist in the agent's environment.
- Agents never start the bot against a real channel, workspace, account or market.
- Conversation/behaviour changes need a scripted scenario test (input sequence → expected outputs) in `<path>`.
- Reviewers additionally check: rate limiting, retries and idempotency on external calls, error replies shown to users, logging of user data.
