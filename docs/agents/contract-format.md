# Validation contract format

Lives at the end of the mission's `spec.md`. Parsed by `scripts/factory/`; keep the headings exact.

The spec itself starts with an intent line, used by `metrics.sh` (D26):

```markdown
**Intent:** feature | maintenance | bugfix | exploration
```

A spec may freeze paths the mission must not change (D61). The patch guard refuses worker changes there before integration; test files under them stay allowed. A maintenance mission without this section freezes `src/`; write `- none` to freeze nothing.

```markdown
## Frozen paths
- `src/` — current behavior is the reference
- *.lock
```

`dir/` freezes everything under it; anything else is a glob (`*` crosses folders). Changing the list is a contract amendment.

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
