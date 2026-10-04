# Pi factory — Step 2, full SDLC

Run AFK issues of any type in parallel, with you on scoping, slicing and arbitration. Quick reference: `CHEATSHEET.md`.

## Lifecycle
```
/tw23-scope   HITL  triage + interview → issues/decisions/*.md → next command
/tw23-plan    HITL  scout (+architect) → grill → PRD → typed issues, Status: todo
/tw23-drain   AFK   queue → batches of 3 parallel-safe issues → routed by Type:
                 feature  /tw23-afk       builder → reviewer ∥ reviewer-2 → documentalist → mr-writer
                 bug      /tw23-bug       debugger → reviewers → (documentalist) → mr-writer
                 refactor /tw23-refactor  refactorer → drift-checker → reviewers → documentalist → mr-writer
                 docs     /tw23-docs      documentalist → reviewer fact-check → mr-writer
                 spike    /tw23-spike     scout → researcher → reviewer-2 challenge → ADR draft
         you   open MRs from .factory/mr/, arbitrate what's waiting
/tw23-wrap          handoff, worktree cleanup list, metrics
```
Out of scope for step 2: CI/CD, deployment, prod ops, dependency upgrades.

## Rule layers
```
~/.agents/AGENTS.md          global: hard rules, factory conventions, run-log schema
  └ kit AGENTS.md            bot now (api, front later): conventions, verification, risks
      └ project AGENTS.md    commands, architecture, doc locations
```
More specific layers win on project facts; nothing overrides global hard rules. Nothing is duplicated across layers. Every agent prompt also points to the global file explicitly, in case subagents don't inherit it.

## Roles and models
| Agent | Model | Thinking | Writes |
|---|---|---|---|
| foreground (scope, plan, issue, arbitrate) | gpt-oss-120b | high | issues, decisions |
| scout | nemotron-3-super-120b | low | nothing |
| architect | gpt-oss-120b | high | nothing |
| researcher | gpt-oss-120b | high | ADR draft |
| drift-checker | gpt-oss-120b | high | nothing |
| reviewer (A) | gpt-oss-120b | high | nothing |
| reviewer-2 (B) | mistral-medium-3-5-0 | high | nothing |
| builder / debugger / refactorer | Qwen 27B | medium / high / medium | code, own worktree |
| documentalist | mistral-medium-3-5-0 | medium | docs |
| mr-writer, handoff | mistral-small-2603 | off | MR text, notes |

Declared but unassigned: gemma-4-31b-it (fallback for Mistral). Nemotron 3 Ultra is not usable in this setup.

Bias warning: the foreground and reviewer A are both gpt-oss. When reviewers disagree, the human arbitrates, not the foreground model.

Design rules: strong tier judges, mid tier executes · structure and behaviour never mix · proof before fix · surgical diff-driven docs · reviewers share one prompt, differ only by model family · max 1 automatic fix round.

## Files
```
global/AGENTS.md          → ~/.agents/AGENTS.md (+ symlink in ~/.pi/agent/)
agent/models.json         → ~/.pi/agent/
agent/settings.json       → ~/.pi/agent/   default = gpt-oss-120b
agent/agents/*.md         → ~/.pi/agent/agents/   (12 agents, managed via /agents)
agent/prompts/*.md        → ~/.pi/agent/prompts/  scope plan drain parallel afk bug refactor docs spike wrap
repo-template/            → each project: AGENTS.md (facts only), issues/TEMPLATE.md, gitignore-additions
kits/                     → layering guide + bot additions (merge into your bot AGENTS.md)
install.sh                optional; copy by hand works the same
```

## Setup notes (tintinweb pi-subagents)
- Agents: `/agents` (no `/subagents-models` in this extension). Project `.pi/agents/` overrides global.
- In `/agents → Settings`: max subagent depth **1** (only the foreground orchestrates), default subagent model **mistral-small**, model scope on only if every model is in `enabledModels`.
- Frontmatter: check `model`, `thinking`, `tools` key names against the tintinweb README; unknown keys are silently ignored. Its skill preloading can replace the "Read …/SKILL.md" lines once verified.
- Worktrees: prompts create them with `git worktree add`. If you switch to tintinweb's built-in worktree isolation, remove those steps — never both.
- Fallback: no automatic fallback for now. Switch by hand in `/agents`. Keep the two reviewers in different families.

## Verify before use
1. Model ids exact (`curl …/v1/models`): `mistral-medium-3-5-0` and the Qwen id were typed from chat/photo. Fix with `grep -rn "model:" ~/.pi/agent/agents`.
2. `/model` (reloads models.json) and `/reload`; check every agent in `/agents`.
3. Context test on a subagent: quote global hard rules, name its skill, give the repo test command.
4. Dry run `/tw23-afk` on a trivial issue: worktree, DONE, two independent reviews, log line, nothing pushed.

## Rollout
Week 1 `/tw23-scope` `/tw23-plan` `/tw23-afk` · Week 2 `/tw23-bug` `/tw23-docs` · Week 3 `/tw23-refactor` after the drift-checker catches a planted change · Week 4 `/tw23-drain` on 3–6 issues, then `/tw23-spike` as needed.

## Step 2 exit criteria
3 mixed-type issues in parallel without conflicts · most AFK issues DONE with no fix round · drift-checker zero misses on planted changes · your time goes to scoping, slicing and arbitration.

Next milestone (step 3): `/tw23-drain` triggered by GitLab events on a server, cost caps, eval set, auto-merge for docs when both reviewers agree.
