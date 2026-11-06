#!/usr/bin/env node
// Plain-writing check (D111): the factory's version of ASD-STE100's
// mechanical rules, on what a person or another agent reads. A script
// decides; nothing here asks a model.
//
// Usage: node prose-lint.mjs [--glossary GLOSSARY.md] <file>...
//        node prose-lint.mjs --glossary GLOSSARY.md   (what the glossary gives the check)
// Prints one finding per line, "<file>:<line>: <rule>: <excerpt>"; exit 1
// when there is any. Code, quotes, links, headings, tables and field lines
// are not prose and are not checked.
import { readFileSync, existsSync } from "node:fs";

const args = process.argv.slice(2);
let glossary = "";
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--glossary") glossary = args[++i] || "";
  else files.push(args[i]);
}

const MAX_WORDS = Number(process.env.FACTORY_PROSE_MAX_WORDS || 25);
// An instruction (a sentence that starts with a command) gets 20 (STE: procedures).
const MAX_INSTRUCTION = Number(process.env.FACTORY_PROSE_MAX_INSTRUCTION || 20);
const COMMAND = /^(?:(?:do not|don't|never|always|then|first|now)\s+)?(run|write|read|use|add|check|keep|put|say|give|make|set|stop|show|list|name|fix|remove|delete|open|call|pass|do|go|leave|take|send|report|cite|compare|choose|copy|move|commit|push|merge|start|wait|ask|answer|record|mark|count|split|find|look|verify|test|build|install|edit|replace|return|skip|try|note|state|quote)\b/i;
// Words that leave the reader to guess (STE: one meaning, no vague words).
const VAGUE = /\b(appropriate(ly)?|properly|as needed|if necessary|etc\.?|and so on|various|should|might|maybe|probably|simply|basically|some kind of)\b/i;
// The passive hides who acts: "the file is written" — by whom?
const PASSIVE = /\b(is|are|was|were|be|been|being)\s+(\w+ed|done|made|written|run|given|taken|shown|seen|known|sent|kept|left|built|found|set|put)\b/i;

// GLOSSARY.md lines that name the words not to use for a term:
//   - **Mission** — one MR's worth of work. Not: task, job
//   | Mission | one MR's worth of work | task, job |   (a third column headed Not/Avoid)
const avoid = new Map();
if (glossary && existsSync(glossary)) {
  const g = readFileSync(glossary, "utf8").split("\n");
  let notCol = -1;
  for (const l of g) {
    const cells = l.split("|").map((c) => c.trim());
    if (/^\|/.test(l) && cells.some((c) => /^(not|avoid)/i.test(c))) { notCol = cells.findIndex((c) => /^(not|avoid)/i.test(c)); continue; }
    let term = "", bad = "";
    const m = l.match(/\*\*([^*]+)\*\*.*?\b(?:Not|Avoid):\s*(.+)$/i);
    if (m) { term = m[1]; bad = m[2]; }
    else if (notCol > 0 && /^\|/.test(l) && !/^\|\s*-/.test(l)) { term = cells[1]; bad = cells[notCol] || ""; }
    for (const w of bad.split(/[,;]/).map((x) => x.replace(/[*`.]/g, "").trim()).filter(Boolean)) avoid.set(w.toLowerCase(), term.replace(/[*`]/g, ""));
  }
}

if (!files.length) {                     // --glossary alone: what the check will use
  console.log(`glossary: ${avoid.size} word(s) to flag${avoid.size ? ": " + [...avoid].map(([w, t]) => `${w} → ${t}`).join(", ") : " (add \"Not: a, b\" to an entry, or a Not column to the table)"}`);
  process.exit(0);
}
const out = [];
for (const f of files) {
  if (!existsSync(f)) continue;
  const lines = readFileSync(f, "utf8").split("\n");
  let fence = false;
  lines.forEach((raw, i) => {
    if (/^\s*(```|~~~)/.test(raw)) { fence = !fence; return; }
    if (fence || /^\s*(#|>|\||<!--)/.test(raw) || /^\s*\*\*[^*]+:\*\*/.test(raw) || !raw.trim()) return;
    const text = raw.replace(/`[^`]*`/g, "CODE").replace(/https?:\/\/\S+/g, "LINK").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/"[^"]*"/g, "QUOTE").replace(/^\s*([-*+]|\d+\.)\s+/, "").replace(/\[(non-)?blocking\]|\[process\]/g, "");
    for (const s of text.split(/(?<=[.!?])\s+/)) {
      const words = s.split(/\s+/).filter((w) => /[A-Za-z]/.test(w));
      const at = `${f}:${i + 1}`, ex = s.trim().slice(0, 90);
      const limit = COMMAND.test(s.trim()) ? MAX_INSTRUCTION : MAX_WORDS;
      if (words.length > limit) out.push(`${at}: long ${limit === MAX_INSTRUCTION ? "instruction" : "sentence"} (${words.length} words, at most ${limit}): ${ex}`);
      const v = s.match(VAGUE); if (v) out.push(`${at}: vague word "${v[0]}": ${ex}`);
      const p = s.match(PASSIVE); if (p) out.push(`${at}: passive "${p[0]}" (say who does it): ${ex}`);
      for (const [w, term] of avoid) if (new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i").test(s)) out.push(`${at}: "${w}" is not this project's word: use "${term}" (GLOSSARY.md): ${ex}`);
    }
  });
}
if (out.length) { console.log(out.join("\n")); process.exit(1); }
