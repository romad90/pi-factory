# Pi factory — cheat sheet

**Cycle:** `/scope` → `/plan` → `/drain` → you open MRs → `/wrap`

## Start
| Command | When | What happens | You |
|---|---|---|---|
| `/scope <need>` | Always first | Classifies (feature/bug/refactor/docs/spike), interviews you, writes `issues/decisions/…md`, tells you the next command | Answer, push back |
| `/plan <topic>` | Big or fuzzy work | scout (+architect) → grill → PRD → typed issues (AFK/HITL, Status: todo, parallel-safe table) | **Validate the slicing** |

Small, clear work: skip `/plan`, run `/issue <decision path>` to write one issue.

## Run
| Command | What happens |
|---|---|
| `/drain` | **Default.** Empties the AFK queue in batches of 3, routed by Type. Stops: queue empty, 2 BLOCKED in a row, or 9 issues. |
| `/parallel a b c` | Same, issues you pick (max 3, must be parallel-safe) |
| `/afk <issue>` | feature: builder → reviewer ∥ reviewer-2 → documentalist → MR text |
| `/bug <issue>` | debugger: failing repro test → root cause → fix → reviewers → MR text (+ same pattern elsewhere) |
| `/refactor <issue>` | refactorer: characterization tests → small steps → **drift-checker** → reviewers → docs → MR text |
| `/docs <branch or module>` | documentalist (diff or legacy) → reviewer fact-check |
| `/spike <issue>` | scout → researcher → reviewer-2 challenges → ADR draft |

Max 1 automatic fix round per issue, then it comes to you.

## It stops and waits for you when
- BLOCKED: unclear issue, design decision, same error ×3, bug not reproducible
- Reviewers disagree or still block after the fix round
- Drift found on a refactor
- Docs contradictions or inferred statements
- Every MR — text ready in `.factory/mr/`, **you** open it

## End
`/wrap` → handoff note, worktrees to clean, day's metrics from `.factory/runs.jsonl`

## Models
| Role | Model |
|---|---|
| Foreground, architect, researcher, drift-checker, reviewer A | gpt-oss-120b |
| scout | nemotron-3-super-120b |
| Reviewer B | mistral-medium (never gpt-oss) |
| builder, debugger, refactorer | Qwen 27B |
| documentalist | mistral-medium |
| mr-writer, handoff, subagent default | mistral-small |
| Manual fallbacks | gpt-oss → Super (not for reviewer B) · Mistral → Gemma · doers: rerun by hand |

## Where things live
- Global rules: `~/.agents/AGENTS.md` (symlinked to `~/.pi/agent/AGENTS.md`)
- Kit rules (bot/api/front) and project facts: `AGENTS.md` in the repo
- Skills: `~/.agents/skills/` · Agents: `/agents` · Prompts: `~/.pi/agent/prompts/`
- Issues: `issues/` · Decisions: `issues/decisions/` · ADRs: `docs/adr/`
