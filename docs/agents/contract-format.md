# Validation contract format

Lives at the end of the mission's `spec.md`. Parsed by `scripts/factory/`; keep the headings exact.

The spec itself starts with an intent line, used by `metrics.sh` (D26):

```markdown
**Intent:** feature | maintenance | refactor | bugfix | exploration
**Reviewer:** <GitLab username of the person who will review the MR>   (optional, D95)
**Design:** yes | no                                                   (optional; default yes for feature and refactor, D94)
```

The reviewer approves the contract and the design with you, so the MR review confirms what was agreed instead of discovering it; `mr.sh` asks them to review the MR.

A spec may freeze paths the mission must not change (D61). The patch guard refuses worker changes there before integration; test files under them stay allowed. A maintenance mission without this section freezes `src/`; write `- none` to freeze nothing.

```markdown
## Frozen paths
- `src/` — current behavior is the reference
- *.lock
```

`dir/` freezes everything under it; anything else is a glob (`*` crosses folders). Changing the list is a contract amendment.

A refactor (D93) changes the code and must not change what it does. Its reference is the tests that pin today's behavior, usually written by an earlier maintenance mission; list them, and the factory refuses any change to them, tests included, and refuses to start without them:

```markdown
## Frozen tests
- `test/characterization/`
```

A refactor's assertions are `Kind: code`: the structure it must reach, and each `AGENTS.md` rule it brings the code under, citing it with `- **Source:** AGENTS.md, <section>`. One `CROSS` assertion states that the frozen tests pass unchanged. A refactor writes no new behavior assertion: new behavior is a feature mission.

```markdown
## Validation contract
**Contract approved:** 2026-10-06

### VAL-<AREA>-<NNN>: <short title>
- **Given:** <starting state>
- **When:** <user input or event>
- **Then:** <what an outside observer sees: reply, tool call, status, stored record>
- **Evidence:** <what proves it: transcript, tool-call log, HTTP status, DB record>
- **Kind:** behavior | code

### Not covered
- <requirement or checklist item>: <reason>
```

Rules:

- IDs are stable once approved. Areas are short uppercase words (`ROUTE`, `KB`, `AUTH`); `CROSS` is for cross-cutting assertions.
- Withdrawn: `### ~~VAL-ROUTE-003~~: <title>` plus `- **Withdrawn:** <date>, <reason>`. Never delete.
- Amended: keep the ID, add `- **Amended:** <date>, <reason>`, set the approval line to `pending re-approval`.
- `Kind: behavior` → checked by `/verify-behavior`, black box. `Kind: code` → checked by `/code-review` on its Spec axis.
- Only the human writes the dated `**Contract approved:**` line (gate G1).

## Example

```markdown
### VAL-ROUTE-001: Known question answered from the knowledge base
- **Given:** the KB contains an article on password reset
- **When:** the user asks "how do I reset my password?"
- **Then:** the bot calls `search_kb` once and answers with the reset steps and a link to the article
- **Evidence:** transcript + tool-call log
- **Kind:** behavior

### VAL-ROUTE-002: Unknown question escalated
- **Given:** the KB has no matching article
- **When:** the user asks an off-topic question
- **Then:** the bot says it can't answer and offers a handoff to a human; the reply cites no KB article
- **Evidence:** transcript
- **Kind:** behavior
```
