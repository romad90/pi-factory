# Bot test harness and instrument

**Status:** to build, as the first mission. Ships in the bots starter kit once stable (D14).

## Two parts, two audiences

| Part | Path | Who sees it |
|---|---|---|
| Harness (the runner) | `./harness` | everyone |
| Instrument (the cases) | `instrument/scenarios/` | validator, CI, human. **Never workers** (D21) |
| Raw results | `instrument/results/<feature>/round-<n>/` | validator only, git-ignored |

**Why the wall:** once a worker can see the sample of cases, the sample becomes the target. Passing it then proves those cases, not the behavior they stand for. Workers get the contract (the requirement) and clustered findings, never the cases. `worktree.sh` leaves `instrument/` out of every worker worktree.

The wall is **soft**: an agent could still read the main checkout or git history. It's enough for Step 2. A separate instrument repo would make it hard, if needed later.

## Running

```
./harness run instrument/scenarios/VAL-ROUTE-001.yaml
./harness run instrument/scenarios            # all cases, as CI does
```

Output: per case, transcript, tool-call log, per-check result, written under `instrument/results/`.

## Case format

One or more files per behavior assertion. See `instrument/scenarios/VAL-ROUTE-001.yaml`.

- `assertion`, `weight` (how much of the behavior this case represents), `runs`, `threshold`.
- `given`: fixtures (KB articles, user profile, mocked tool responses).
- `turns`: user messages in order.
- `checks`: **deterministic by default** (D22): `tool_called`, `tool_not_called`, `tool_call_count`, `reply_contains`, `reply_not_contains`, `reply_matches`.
- `relaxations`: anything non-deterministic, such as an LLM `judge`. Each relaxation carries a `license` explaining why an exact check isn't possible. No license, no relaxation.

## Growing, never shrinking (D23)

The validator adds cases whenever it learns where behavior lives, especially when successive rounds stop revealing failures: that usually means the instrument is too thin, not that the bot is done. Changing or deleting a case needs `/contract amend` in the same MR; CI enforces it.

## Nondeterminism (D15)

Each case runs `runs` times and passes at `threshold`. Some passes below threshold = `FLAKY`, counted as a fail and reported separately.

## Open choices

- Local instance vs. preview environment (Step 2 default: local, port from `.env.factory`).
- Mocked vs. real tools (default: mock external systems, keep the LLM real).
- Judge model: different family from the bot's model.
