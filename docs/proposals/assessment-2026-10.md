# Assessment after mission 2 (October 2026)

Mission 2 finished: 10 tickets, behavior and health PASS, 34 characterization tests, production code byte-identical. It also cost 31 human decisions against a target of 5, and nine days. This page sorts the proposals (P1–P10) and the ideas borrowed from other factories ([ideas](ideas.md)) by what the mission showed, and names the batch to build before mission 3.

## What the mission showed

1. **The lead's model mattered more than any rule.** gpt-oss-120b improvised three times despite the guard (D71) and the prompt rules (D74), the last time by inventing a passed integration. GLM followed the script through a missing install, a 403 and a dirty tree, stopping and quoting the rule each time.
2. **Most lost rounds were hand-overs the worker never checked** (finding 53). The self-check existed; nothing made it happen.
3. **One human note did what three rounds couldn't** (finding 54): the pitfalls, and the passing tickets to copy.
4. **The environment, not the code, stopped the factory**: two keys with different models, a missing `/v1`, an incomplete Pi install (findings 56–58).
5. **The scripts held.** Every stop of the last two days was a script saying no for a reason (provider error, dirty tree, fix-lane limit), and none lost work.

## What pi-subagents 0.76.1 allows (read from its docs, October 2026)

| Question | Answer | Consequence |
|---|---|---|
| Can a workflow run a command after a worker? | Not from our script files; but each child accepts a `gate` command run in its worktree when it finishes | D78: the self-check as a gate (opt-in) |
| Can a failed worker continue in the same session? | `runs.run(key, { resume: runId, task })`, if the worktree still exists | D78: one same-session retry |
| Kill a worker that goes silent? | No. `control.needsAttentionAfterMs` only notifies; only `timeoutMs` kills | Stall detection needs our own watch (P10 health findings) |
| Per-run tokens? | `{runId}_{agent}_meta.json` per child (`usage`: input, output, cache, cost, turns) | `usage.tsv` can be read after a wave |
| Run a workflow without an LLM lead? | No CLI; an extension can request one over pi-subagents' in-process RPC (async) | P2 is a small Pi extension, not a shell script |
| Model fallback on failure? | None built in | Escalation stays ours (worker → heavy worker) |

## Proposals

| # | Proposal | After mission 2 | Decision |
|---|---|---|---|
| P1 | Several gateways | Two gateways were real on day one of the second machine | **Partly done** (D79: probe per provider). Fallback chains: later |
| P2 | The lead becomes a script | The strongest finding; but GLM as lead removed most of the drift | **Next big item**, as a Pi extension driving `next.sh` and workflows over RPC. Not before mission 3 |
| P3 | Maintenance lane | Mission 3 is characterization again, the lane's first step | Keep; mission 3 is its evidence |
| P4 | Director and triggers | Needs P2 | Later |
| P5 | Continuous improvement | Needs P3, P4 | Later |
| P6 | Control room | Needs P2, P4 | Later; P10 is its first piece |
| P7 | Launch gate | No evidence yet | Later |
| P8 | Hands-off mission | 31 decisions; 3 in the last two days | Continue: steps 5–6 |
| P9 | Rounds that converge | Findings 53–55, 66 | **Steps 5 and 6 done**, step 1 in the brief (reproduce first; the `REPRO:` check in `collect.sh` is next); 2–4 next |
| P10 | Front page | Hours spent reading terminals to learn the state | **Before mission 4**: `runs.tsv` (D77) is its first data |

## Borrowed ideas, sorted

| Idea | From | Status |
|---|---|---|
| Self-check enforced, failure corrected in the same session | SSSF, Atelier | ✅ D78 (opt-in gate + resume) |
| Provisioning check before spending tokens, per provider | Machinist | ✅ D79 |
| Rationalization ("I'll assume") named in the briefs | afonsoft | ✅ worker and reviewer briefs |
| Reproduce first in fix rounds | afonsoft | ✅ worker brief (`REPRO:`) |
| Contract doubts raised by workers | afonsoft (three strikes), DoorDash | ✅ worker brief (`CONTRACT DOUBT:`); clustering in `next.sh`: next |
| Explicit escalate list for an approver | zazencodes | Already the resolver's never-auto list (D70) |
| Runs and models recorded per role | Atelier, Bernstein | ✅ D77 (`runs.tsv`) |
| Journal between rounds | Machinist, afonsoft, DoorDash | Next (P9 step 2) |
| Measured progress, stop when a round fails like the last | DoorDash, Bernstein | Next (P9 step 3) |
| Token log per run | Machinist, Bernstein | Next: read `_meta.json` after a wave |
| Stall by silence, not duration | Symphony, Anneal | Next: a watch on the run's `status.json` (P10) |
| Escalate by model, then by effort | Bernstein, Gas Town | Done by role (D24); per-retry effort: later |
| Isolated worker launch | Anneal | Mostly in place (`systemPromptMode: replace`, `inheritSkills: false`, no ambient extensions in foreground children); `inheritProjectContext` stays on for AGENTS.md |
| Stages as data; phases start as failed; typed results | Mastra, SSSF, Atelier | Design of P2 |
| Static front page polling one snapshot | zazencodes, Symphony | Design of P10 |
| Health findings with evidence and a repair | Mastra | Design of P10 |
| Every rule written twice, with a fixture that fires | software-factory | Later: the guard and resolver tests already do it for their rules |
| Read-only judges enforced by lint | Machinist | Later (`models-lint` reading `tools:`) |
| Hash chain over `decisions.tsv` | Bernstein | Later |
| LLM coordinators, heavy stacks | Gas Town, sgai, Symphony, afonsoft | **Rejected**: mission 2 showed the opposite works |

## Before mission 3

Done in this change (D75–D79): axes and fix-lane questions, the fix-lane limit, models per role, the self-check record and gate, the per-provider probe, the brief lines, the characterization rules.

To do on your side, once:

1. Upgrade the target repo (`install-into.sh … --no-branch`), then `node scripts/factory/models-probe.mjs --stamp` and commit the stamp, **on each machine**.
2. Lead: GLM (or your strongest instruction follower), thinking low.
3. Try `FACTORY_SELF_CHECK_GATE=1` on the first wave of mission 3. If pi-subagents refuses the gate, the wave fails at once with its error: remove the line and continue; nothing is lost.

Next factory work, in order: P9 steps 2–4 (journal, no-progress escalation, contract doubts clustered), `usage.tsv`, then P10, then P2.
