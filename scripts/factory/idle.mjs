#!/usr/bin/env node
// The newest sign of life of a running wave (D151, B12): the latest change, at
// or after <since-ms>, to the runner's own log or to a run's transcript.
// pi-subagents appends one record to a run's transcript per message, tool call
// and result, so a run that is working writes there every few seconds or
// minutes; one whose model call never returns writes nothing.
//
// Usage: node idle.mjs <since-ms> <file-or-folder>...
// Prints "<newest-ms> <path>" (the wave's start and "-" when nothing changed).
// Folders are searched for *.jsonl files, 7 levels down, as archive.sh looks
// for runs (FACTORY_USAGE_DIRS). Best effort: an unreadable folder is skipped.
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const [sinceArg, ...paths] = process.argv.slice(2);
const since = Number(sinceArg) || 0;
let best = since, where = "-";
const seen = (p, ms) => { if (ms >= since && ms > best) { best = ms; where = p; } };
function walk(dir, depth) {
  let entries; try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { if (depth < 7) walk(p, depth + 1); continue; }
    if (!e.isFile() || !e.name.endsWith(".jsonl")) continue;
    try { seen(p, statSync(p).mtimeMs); } catch {}
  }
}
// Folders first: on a tie (file times can be that coarse) a run's transcript
// names the run, the runner's log does not.
const stats = paths.map((p) => { try { return [p, statSync(p)]; } catch { return null; } }).filter(Boolean);
for (const [p, s] of stats) if (s.isDirectory()) walk(p, 1);
for (const [p, s] of stats) if (!s.isDirectory()) seen(p, s.mtimeMs);
console.log(`${Math.floor(best)} ${where}`);
