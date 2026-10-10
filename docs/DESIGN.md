# How the factory works, and why

This is the readable version of the design: one page per idea, what it does and the reason behind it. The [ADR](adr/ADR-001-agentic-factory.md) holds every decision in order (D1–D54) with its history; this guide groups them by concept and links back. For what to type, see the [cheat sheet](../CHEATSHEET.md).

---

## 1. The problem it solves

Agents write code fast. What they don't do on their own is **know when they're done, judge themselves honestly, keep the codebase healthy, or stay out of trouble**. A single agent session that plans, builds, reviews and reports will happily approve its own work, invent a model name in its verdict, and declare victory on a feature nobody specified.

The factory turns that into a loop you can trust without reading every line:

1. **You decide what "done" means** before any code exists.
2. **Different agents build, judge and validate**, each starting fresh, with judges from another model family.
3. **Scripts, not models, decide what happens next** and keep the record.
4. **CI enforces the gates** on every merge request.

Two constraints shape everything: it runs **from one laptop** under a **shared, small request quota**, and it must stay **lean and understandable**: shell scripts, markdown and files in git, no service to operate.

## 2. Five principles

| Principle | Why |
|---|---|
| **Fresh context per role** (D2, D30, D32) | A subagent only knows what its brief says. If the lead summarizes its own reasoning into the brief, its bias travels with it. Briefs are generated from file paths, never written by the lead, and the gate checks their ID. |
| **The contract before the code** (D4–D7) | Without a written definition of done, every later step converges confidently on whatever the first agent assumed. A critic attacks the contract and a human approves it, so the most important artifact gets the most scrutiny. |
| **Judges report, never fix** (D12) | A reviewer that fixes what it finds becomes a builder whose work nobody reviews. Findings become tickets; a wrong assertion becomes an amendment. |
| **State in files, committed** (D3, D46) | A conversation is lost when a session crashes or a context fills up. Files survive, any session can pick up, and git is the audit trail. |
| **Judges from another model family** (D13, D31) | A model shares blind spots with itself and its relatives. The critic is never the author's family, reviewers and the steward are never the workers', and a lint enforces it in CI. |

## 3. The loop: scripts decide, the lead relays

```
/factory <feature> → next.sh prints STEP: <code> → the lead acts → repeat
```

`next.sh` reads the mission's files and prints one step. Machine steps (`contract`, `build`, `review`, `validate`, `health`, `steward`…) run a script or a generated workflow; human steps (`approve`, `decide`, `approve-tickets`, `unverified`, `pr`…) stop the loop and notify you.

**Why:** a model choosing the next step drifts, skips, or loops (mission 1's lead once repeated "20.20.20…" until stopped). A state machine over files is deterministic, testable without a model (`tests/factory.test.sh` plays a whole mission), and the lead's only job is to relay: run what the script says, pass workflow files by path, stop for humans (D33).

## 4. Defining done

| Step | What happens | Why |
|---|---|---|
| Spec | You grill the idea and write `spec.md` | The spec decides what value is; a model guessing it optimizes the wrong thing. |
| Contract | An author writes `VAL-AREA-NNN` assertions (Given / When / Then) | Checkable statements, not prose, so every later judge checks the same thing. |
| Critique | A critic from another family attacks it, with a domain checklist | Mission 1's critic caught a missing cap and a contradictory assertion before any code. |
| Approval | `/factory-approve` writes a dated line | The definition of done is yours; a one-word command keeps it cheap without making it implicit (D43). |
| Amendment | `/factory-amend "<change>"` removes approval and reruns author + critic | Contracts are wrong sometimes; the fix goes through the same scrutiny, never a quiet edit (D7). |

## 5. Building

**Tickets** (D52) are drafted by the ticket writer from the approved contract, each with `## Covers` (the assertions it makes true) and an honest `**Size:**`; you approve them in one word. *Why:* in mission 1, tickets written by hand needed fixing by hand, and approving a plan is cheaper than writing it. `coverage.sh` (G2) then checks every assertion is covered.

**Workers** build one ticket each, in parallel, each in its own git worktree, with TDD (D16, D35). *Why:* isolation lets tickets run side by side without stepping on each other, and a failed ticket can be thrown away.

**The wall** (D21): behavior test cases live in `instrument/`, which worker worktrees don't contain, and the command guard blocks routes to it. *Why:* once a builder can see the exact sample it's judged on, the sample becomes the target.

**Escalation by model** (D24, D52): a ticket that failed twice, or is marked `Size: L`, goes to the heavy (frontier) worker. *Why:* efficient models for the common case, expensive ones only where evidence says they're needed.

**Integration** (D34, D44, D51): `integrate.sh` applies the worker's patch only after the patch guard passes, then runs lint, tests and your extra check, and commits only if everything is green. Otherwise the failure is recorded as a round. *Why:* reviewers then only spend effort on code that already works, and no integration happens without tests.

## 6. Judging

**Reviewers** check each integrated ticket against its assertions, in a fresh context, on another family (D2, D13). **The validator** runs the hidden instrument against the whole feature and reports findings clustered by root cause, never case contents (D14, D25).

**Records the factory can't overstate** (D38–D40):

| Mechanism | Why |
|---|---|
| Rounds come from verdict history (`<stem>.rN.md`), written by `collect.sh` | Mission 1 showed "round 1" after two failures, and metrics claimed 100% first-pass. An agent shouldn't count its own attempts. |
| The model in a verdict is the configured one | Models guess who they are; every mission 1 verdict named a model that wasn't in use. |
| A run without a patch, a red integration, a blocked patch: each is a recorded round | Otherwise escalation needed a hand-written verdict. |
| Every assertion is `PASS — evidence`, `FAIL`, or `UNVERIFIED — why` | Mission 1 reported every behavior assertion as passed with no harness. Unverified behavior now needs a named human's acceptance and shows up as a Known limit in the MR. |

## 7. Code health: the codebase is the fuel (G5)

The codebase is what the team uses to bring value to customers, so every mission must leave it **safe, understandable by any human, battle-tested and predictable** (D49, D50).

1. **Measured first:** `health.sh` compares duplication, large files, deep nesting, debt markers and skipped tests to a committed baseline, and runs your own tool. A mission may improve the numbers, never make them worse.
2. **Then judged:** the code steward reads the **whole mission diff** against `docs/agents/quality-bar.md` (the `QB-` items), with evidence per item, and explains every changed file in three sentences. The gate fails on a file it couldn't explain.

**Why both:** per-ticket reviews see small diffs, and erosion happens across them: the same logic three times, a clever abstraction, an untested failure path. Measurement catches what is countable without spending a request. Judgement catches what isn't, against a bar written down rather than everyone's opinion. A ratchet improves a codebase without a big-bang cleanup: old debt isn't the mission's fault, but no mission may add to it. And a file a fresh model can't explain is a file a newcomer won't understand.

## 8. Humans: few decisions, never watching

| Mechanism | Why |
|---|---|
| One-word gates: approve, decide, amend, accept-unverified, approve tickets (D43) | Approvals typed by hand into files got skipped or mangled; a command writes the line, logs it, checkpoints. |
| `decisions.tsv`, read by every role (D43) | In mission 1, decisions lived only in chat; agents now read your answers and they win over agent judgement. |
| Irreversible choices never default (D47) | A worker timed out on a question and picked the option the spec had ruled out. Deletes, secrets, production behavior and the contract now stop the mission until you answer. |
| Notifications on every human step, pause and resume (D45) | Long waves were watched by hand; a VPN cut or a full context forced restarts from memory. |
| Pre-flight and automatic checkpoints (D46) | A dropped VPN produced seven errors instead of one message; checkpoints were typed about ten times per mission. |

The full table of what is manual, what is automatic and why is in [the cheat sheet §1](../CHEATSHEET.md#1-who-does-what-manual-automatic-and-why).

## 9. Safety: agents can't do harm

Agents have bash on your laptop, with your identity. "Please don't" in a prompt is not a control. There are two guards (D51):

- **Command guard** (live): a Pi extension blocks dangerous tool calls by the lead and every agent: pushes and history rewrites, `--no-verify`, `sudo`, recursive deletes of `/ ~ .. .git`, cluster/cloud/secret-store changes, uploads and remote shells, credential reads, publishing, merging, writes to the factory/CI/hooks, routes to the instrument. A blocked agent stops and asks; it never looks for another way.
- **Patch guard** (deterministic): every worker patch is checked before integration. No changes to the instrument, the factory, CI or hooks; no deleted, skipped or focused tests; no silenced checks; no secrets. A block is a recorded round.

**Why two:** the live guard prevents harm before it happens but depends on Pi loading the extension. The patch guard can't be skipped and holds even if the extension doesn't load. **What it is not:** a sandbox. A deny-list stops known dangerous commands, not every possible one. Real isolation (OS sandbox, short-lived credentials, kill switch) is the bar for Step 3.

## 10. Agnostic machinery, owned content

The factory builds and maintains bots, APIs, front ends and batch jobs, in any language. Nothing domain-specific lives in its scripts or roles (D54). What it knows about *your* work comes from files you own:

| File | Holds | Read by |
|---|---|---|
| `AGENTS.md` | your company's engineering taste, for everything | every agent |
| `docs/agents/quality-bar.md` | the code health bar | the steward (G5) |
| `packs/<name>/` → `contract-checklist-<name>.md`, `quality-bar-<name>.md` | practices for a kind of software (`api`, `batch`, `bot`) | the contract author and critic (G1), the steward (G5) |

**Why content, not code:** a factory that knows "APIs" in its scripts is neither agnostic nor lean. Markdown read by the existing roles adds knowledge without adding machinery, and you can read, edit and prune it. Install a pack on a blank page, where conventions cost nothing (the `api` pack is Stripe-inspired). On existing code, prune it first: consistency with what's there beats any ideal, and the steward judges the diff, never the past.

## 11. Enforcement: gates nobody can skip silently

| Mechanism | Why |
|---|---|
| CI runs the gates on every MR (`gate.sh`, D9) | A gate run only on the laptop is advisory; "Pipelines must succeed" makes it real. A `factory:bypass` label exists, visible and counted. |
| Lanes from `behavior-paths` (D11) | Changing behavior requires a mission; small non-behavior changes take the light lane. The size of the process follows the risk of the change. |
| Fix lane with blast radius (D41) | A three-line fix shouldn't cost a mission, nor bypass every gate. It gets checks, the patch guard and one fresh reviewer. |
| Behavior verdicts stale only on behavior paths; G5 only on source files (D42) | Re-validating after a README edit wastes scarce requests. |
| Install through its own MR (D48) | Tooling hid the feature in mission 1's MR (193 files). |
| Skills pinned by checksum (D36), models linted (D31) | "Use version X" and "judges on another family" must be checkable, not conventions. |

## 12. What it deliberately doesn't do

| Not this | Why |
|---|---|
| A second skill collection or router | Same-job skills override each other silently. mattpocock/skills v1.3.1 is the only foundation; ideas from elsewhere are borrowed as content. |
| An orchestration service or graph engine | Files, git and a state machine in bash are enough for one laptop, and anyone can read them. |
| Pi Durable, for now | A framework for durable agent applications: a second architecture on an experimental API. It's the candidate for an unattended Step 3 runner, with these scripts staying the brain (roadmap X13). |
| Token optimizations | The bottleneck is requests per window, not tokens. |
| Hosted bots and apps | Code and history would leave your environment. |

## Where to go next

- What to type: [CHEATSHEET.md](../CHEATSHEET.md)
- Every decision, in order, with its history: [ADR-001](adr/ADR-001-agentic-factory.md)
- Where this stands on the adoption ladder: [LADDER.md](LADDER.md)
- The mission that shaped v1.0 and v1.1: [case study](case-studies/mission-01.md), [retro](retros/mission-01.md)
- What's next: [ROADMAP.md](ROADMAP.md)
