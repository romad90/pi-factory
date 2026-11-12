# P33. Several angles on the contract at once: an adversary, a grounding check and a naive reader

**Status:** draft: the eslint-10 replay decides between it and P28 alone (see the [November assessment](assessment-2026-11.md)) · **Effort:** M · **Depends on:** the contract step (`workflow.sh contract`), P28 (packs feed the adversary)

## Problem

The contract has one critic. Code review already runs two axes in parallel, Standards and Spec (the `code-review` skill; `.factory/briefs/reviewer.md`, line 5). The contract, which every later gate trusts, gets one reader with one question.

eslint-10 shows what that costs:

- **Six blocking findings over four rounds** (2, 1, 1, then 2), all of one kind: a weaker configuration that still passes. One critic found them a round at a time. Five amendments and one decision followed: 6 of the mission's 11 human decisions.
- **Nobody ran anything.** Neither the author nor the critic ran a command; both said so. Four of the mission's decisions carry the words "checked by the person": the person verified `--print-config`, the 143 globals, the probes and the reference config by hand, on ESLint 10.
- **Two facts in the contract were wrong** and only the worker found them, at build time: "exactly six keys" (ESLint prints nine) and "694 total" (the base gives 695).
- **The critic's summary came back empty twice**, and the lead couldn't tell whether a critique existed.

## Source

Google's Elephant-Goldfish Model plugin (`google/elephant-goldfish-model`, Apache-2.0, read at its source, November 2026). Its review runs five stages with eight reviewer personas and a synthesizer that runs a stage's reviewers in parallel and merges their findings. We borrow three of its rules and one persona, not the set:

- a reviewer that returns nothing "did not review": retry once, then mark it "not run", never "no findings";
- at most one re-audit per stage; what is left is recorded as an accepted trade-off;
- the naive reader paraphrases the document before judging it, and the author compares the paraphrase with the intent.

Its structure, style and design-risk personas are left out: our evidence doesn't ask for them, and prose lint covers style.

## Design

Three angles run in parallel in the contract step, each a fresh agent with its own brief:

| Angle | Question | Output |
|---|---|---|
| **Adversary** (today's critic) | Which wrong change would pass every assertion? (D126) | findings with "Passes wrongly" |
| **Grounding** (new) | Is every command, option, count and file the contract names true on the base commit and on the target version? It runs them, in `.scratch/<mission>/tmp/copies/`. | each fact as checked, wrong (with the real value) or not checkable (with why) |
| **Naive reader** (borrowed) | What will change, and what won't, said in its own words; which term is undefined? | a paraphrase, shown on the gate page; findings only for undefined terms |

A script, not a model, merges the three files into `contract-critique.md`: findings by level, each tagged with its angle, and a status line per angle (`completed` or `not run`). An angle with no output is retried once, then `not run`, and G1 says so.

One more round at most. After the second critique, open findings go to the gate page as "accept or amend", and the person decides once.

The grounding angle needs the target version installed. Until P31 exists, it runs after the person's dependency commit when the mission has one, and says "not checkable before the install" otherwise.

## Steps

1. The merge script and the `not run` status, with today's single critic as the only angle. Test: an empty critic output gives `not run` at G1, never "no blocking findings".
2. The grounding angle. Test on a fixture contract with one wrong count and one missing option: both reported with the real value.
3. The naive reader and its paraphrase on the gate page.
4. The round cap.

## Outside check

Replay on eslint-10. The first contract draft is still in the gym's pull request 9 (commit `b3fff97`, 14 assertions).

- The adversary and grounding angles together name at least 5 of the 6 recorded blocking findings in round 1.
- The grounding angle reports nine keys for `no-unused-vars` and 695 assertions, without a person.
- Cost of the three angles in tokens, against the six single-critic rounds it replaces.

It fails if round 1 finds fewer than 4 of the 6: then angles don't replace rounds, and P28's pack is the cheaper fix alone.

## Open questions for Rode

- The same model family for all three angles, or the grounding angle on the worker's family (it runs commands)?
- Is one re-audit enough, or two for missions that touch `lib/`?

## Not doing

No brainstorm or draft skill from the plugin (grill-me and the contract author do that). No second copy of the same reviewer for recall: that is P23's question, with its own measurement.
