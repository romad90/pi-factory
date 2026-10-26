---
name: deep-prompt
description: Turn a task described in a few lines into a deeper version before a spec is written, by answering four questions (what an expert would add, the rawest material, the methods and tools, what outside check proves it right). Use before /grill-with-docs, or when the human says deep-prompt or genius-mode.
---

# Deep prompt

A deeper version of a task, not a bigger one: done the way the best practitioners of the field would do it, with a check that doesn't depend on the model or the human. From Felix Rieseberg, "How to be more ambitious: a tutorial for humans with models" (the Depth practice).

In the factory it runs before the grilling: its answers become the spec's starting point, and its outside check becomes candidate contract assertions. It never starts the work.

## Step 0: size it

If the task is small, mechanical or already precise (a rename, a one-line fix, a fix-lane change), say so in one line and stop: the fix lane or the original request is the right size. Depth costs time and tokens.

## Step 1: answer four questions, concretely

1. **What a top professional in this field would do here that wasn't asked for.** Name the practitioner (SRE, staff engineer on developer platforms, data engineer, security reviewer…) and the moves they would make. Their methods, never their voice: no role-play.
2. **The rawest material they would start from**, instead of what has already been digested: the code and its git history, logs, run transcripts, real payloads, the CI file, production signals; not a summary, an audit report or a retro. Say where each one lives in this repo or system, and what reading it needs.
3. **The specific methods and tools they would use**: named techniques and instruments (characterization tests, mutation testing, golden files from real payloads, property-based tests, a profiler, a query on the real table), not vocabulary.
4. **What, other than the model or the human, would show the result is right**: a test that fails before and passes after, a tool's measurement (mutation score, latency, error rate), a third person, a reproduction on another machine, production data. If none exists, say so plainly: that is the first thing to build.

When it changes the answer, also:
- **Altitude**: the outcome wanted after this task, and whether another task reaches it better.
- **Range**: one method borrowed from another field.

## Step 2: write it down

Write `.scratch/<mission>/depth.md` (or show it, when there is no mission yet):

```markdown
# Depth: <task in one line>

**Outcome:** <what should be true after, at altitude>
## Expert moves
## Raw material
- <source> — <where> — <how to read it>
## Methods and tools
## Outside check
- <check> — passes when <observable condition>   (candidate assertion)
## Not doing
- <what was considered and left out, and why>
```

Each outside check is written so the contract author can turn it into an assertion with an ID. Then start the grilling on it: `/grill-with-docs` with `depth.md` named as its first input, so it asks only what `depth.md` leaves open.

## Step 3: stop

End with one question: go with the deeper version, edit it, or keep the original. Nothing else happens until the human answers.
