# Plain writing (what a person or another agent reads)

Your text is read by models of other families and by people whose first language is not English. A sentence two readers understand differently is a defect. These rules borrow the mechanical part of ASD-STE100 (Simplified Technical English). `scripts/factory/prose-lint.mjs` checks them on the spec, the strategy, verdicts and the MR description.

1. One sentence, one idea. At most 25 words; an instruction, at most 20.
2. Say who acts. Write "the worker writes the file", not "the file is written".
3. Write an instruction as a command: "Run the tests." Put one instruction in a sentence.
4. Use one word for one thing. Use this project's terms as `GLOSSARY.md` defines them. Do not change words for style: a mission stays a mission.
5. Do not use words that leave the reader to guess: appropriate, properly, as needed, if necessary, etc., various, should, might, maybe, probably, simply.
6. Write a requirement with "must" or "does". Write a fact as a fact, with its evidence.
7. Write numbers and names exactly: a file path, a command, a count. Put code, commands and paths in backticks.
8. Keep a paragraph to one topic, six sentences at most.

Not prose, not checked: code, commands, quotes of an error or of a person, links, headings, tables, field lines (`**Commit:** …`), commit messages (commitlint checks them), and the person's job line.
