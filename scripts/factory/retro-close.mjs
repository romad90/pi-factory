#!/usr/bin/env node
// The retro's last section, written after the merge (P23): what the factory's
// own gates could not see. retro.sh close fetches the MR and its notes, then
// calls this to write "## After the merge" into the private retro (replacing
// the section when run again; the labels already set are kept).
//
// Usage: node retro-close.mjs <retro.md> <mr.json> <notes.json> <reverts.tsv> [bots]
//   reverts.tsv: "<sha>\t<subject>\t<reverted sha>" per revert commit found in git
//   bots: space-separated usernames whose notes are tools, not reviewers
//
// Review comments are candidate recall misses, never counted as misses on
// their own: a comment can be a preference, a question, a typo. Each one is a
// line the human labels by replacing "[ ]" with "[miss]" (the factory's
// reviewers should have caught it) or "[ok]" (not a miss). `factory learn`
// counts the labels: recall misses per mission, the input P23 needs.
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const [retroFile, mrFile, notesFile, revertsFile, bots = ""] = process.argv.slice(2);
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const json = (f, d) => { try { return JSON.parse(read(f)); } catch { return d; } };
if (!retroFile || !existsSync(retroFile)) { console.error(`retro-close: no retro at ${retroFile}`); process.exit(2); }

const mr = json(mrFile, {}), notes = json(notesFile, []);
const botSet = new Set(bots.split(/\s+/).filter(Boolean));
const author = mr.author && mr.author.username;
const reviewNotes = (Array.isArray(notes) ? notes : [])
  .filter((n) => n && !n.system && n.author && !n.author.bot && !botSet.has(n.author.username) && n.author.username !== author)
  .sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));

const old = read(retroFile);
const cut = old.search(/^## After the merge\b/m);
const before = (cut >= 0 ? old.slice(0, cut) : old).replace(/\s*$/, "\n");
// Labels already set survive a re-run: keyed by the note id.
const kept = new Map();
for (const m of (cut >= 0 ? old.slice(cut) : "").matchAll(/^- \[(miss|ok)\] .*\(note (\d+)\)/gm)) kept.set(m[2], m[1]);
const escaped = (cut >= 0 ? old.slice(cut).match(/### Escaped defects[^\n]*\n([\s\S]*?)(?=\n### |\s*$)/) : null);

const reverts = read(revertsFile).split("\n").filter(Boolean).map((l) => l.split("\t"));
const one = (s) => String(s || "").replace(/\s+/g, " ").trim();
const L = [];
L.push(`## After the merge (retro.sh close, ${new Date().toISOString().slice(0, 10)})`, "");
L.push(`- MR: ${mr.web_url || "?"}, ${mr.state || "?"}${mr.merged_at ? ` on ${String(mr.merged_at).slice(0, 10)}` : ""}${mr.merged_by ? ` by ${mr.merged_by.username}` : ""}`);
L.push(`- Reverts of the merged change: ${reverts.length ? reverts.map((r) => `${r[0].slice(0, 8)} "${one(r[1])}"`).join(", ") : "none found"}`, "");
L.push("### Review comments (candidate recall misses: replace [ ] with [miss] or [ok])", "");
if (!reviewNotes.length) L.push("- none");
for (const n of reviewNotes) {
  const where = n.position && (n.position.new_path || n.position.old_path) ? ` ${n.position.new_path || n.position.old_path}${n.position.new_line ? `:${n.position.new_line}` : ""}` : "";
  L.push(`- [${kept.get(String(n.id)) || " "}] @${n.author.username}${where}: ${one(n.body).slice(0, 240)} (note ${n.id})`);
}
L.push("", "### Escaped defects (found after the merge by anyone or anything: one line each, what, where, how found)", "");
L.push(escaped && escaped[1].trim() ? escaped[1].trim() : "- none recorded");
writeFileSync(retroFile, `${before}\n${L.join("\n")}\n`);

const misses = [...kept.values()].filter((v) => v === "miss").length;
console.log(`retro close: ${reviewNotes.length} review comment(s) to label (${misses} labelled miss so far), ${reverts.length} revert(s); written to ${retroFile}`);
