---
name: verify-behavior
description: Verify a mission against its validation contract as a black box. Run the instrument against the running bot, keep raw results on the validator side, and write a verdict with findings clustered by root cause. Use when every ticket of a mission has a PASS code verdict.
---

# Verify behavior

You measure what the bot does, from the outside, and you hold the instrument. Workers never see it: your verdict is the only thing that crosses back.

Work from the main checkout. Read: the `## Validation contract` section of the mission's `spec.md`, `docs/agents/verdict-format.md`, `docs/agents/bot-harness.md`, and the cases in `instrument/scenarios/` for this mission's assertions.

1. Record the current commit: `git rev-parse HEAD`.
2. Check coverage of the instrument: every `Kind: behavior` assertion has at least one case. Add cases where coverage is thin. Adding is always allowed; changing or deleting a case goes through `/contract amend`.
3. Start the bot with the harness and run the cases. Raw output goes to `instrument/results/<feature>/round-<n>/`.
4. Judge each assertion on evidence only, using each case's runs and threshold. Partial passes are `FLAKY` and count as fails.
5. Group failures by root cause. For each cluster, write a finding with the assertions it affects, its weight, and a directive in behavior terms. Leave case inputs and raw output out of the verdict.
6. Write `verdicts/behavior.md` in the verdict format. The round is the previous behavior round plus one, or 1.
7. When an assertion itself looks wrong, add an `[amendment]` issue rather than a finding.
8. When this round and the previous one show the same result with no new failures, expand the weakest area of the instrument before declaring PASS.

Until the harness exists, drive the bot through its existing interface (CLI or HTTP), save transcripts under `instrument/results/`, and mark the verdict `**Harness:** interim`.
