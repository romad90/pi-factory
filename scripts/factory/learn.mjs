#!/usr/bin/env node
// factory learn: what every mission on this machine taught, across projects,
// scrubbed so it can be shared. Reads the private data folder only
// (${FACTORY_DATA_DIR:-~/.pi-factory/data}/<project>/retros/*.md and their
// .metrics.json, written by retro.sh save), never a repository.
//
// Usage: node scripts/factory/learn.mjs [--json] [--raw]
//   --raw  no scrubbing: for your own eyes, never to share
//
// Scrubbing (the default): project folders become <project-N>, missions
// <mission-N>; URLs, host names, e-mail addresses, home paths and this user's
// names become placeholders; every line of ~/.pi-factory/scrub-terms (one term
// per line: a company, a team, a product) becomes <term>. Then a last check:
// if any project name, mission name or scrub term is still in the output,
// nothing is printed (exit 3). Read the output before sharing it anyway.
//
// Recurrence: findings are grouped when their key words overlap (Jaccard ≥ 0.4
// on words of 5+ letters); a group seen in several missions, above all in
// several projects, is the factory's flaw, not one project's.
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, basename } from "node:path";
import { homedir, userInfo } from "node:os";
import { execFileSync } from "node:child_process";

const argv = process.argv.slice(2);
const raw = argv.includes("--raw"), asJson = argv.includes("--json");
const root = process.env.FACTORY_DATA_DIR || join(homedir(), ".pi-factory", "data");
if (!existsSync(root)) { console.log(`learn: no data folder at ${root} yet (missions save their retro there: retro.sh save)`); process.exit(0); }

const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const projects = readdirSync(root).filter((p) => { try { return statSync(join(root, p)).isDirectory(); } catch { return false; } }).sort();

// --- collect -------------------------------------------------------------------
const missions = [], findings = [];
for (const p of projects) {
  const rd = join(root, p, "retros");
  if (!existsSync(rd)) continue;
  for (const f of readdirSync(rd).filter((x) => x.endsWith(".md")).sort()) {
    const mission = f.replace(/\.md$/, ""), text = read(join(rd, f));
    let m = {}; try { m = JSON.parse(read(join(rd, `${mission}.metrics.json`)) || "{}"); } catch {}
    missions.push({ project: p, mission, metrics: m });
    let header = null;
    for (const line of text.split("\n")) {
      if (!/^\s*\|/.test(line)) { header = header && line.trim() === "" ? header : header; continue; }
      const cells = line.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
      if (/^-+$/.test(cells[0].replace(/:/g, ""))) continue;
      if (!header && cells.some((c) => /^finding$/i.test(c))) { header = cells.map((c) => c.toLowerCase()); continue; }
      if (!header) continue;
      const col = (name) => cells[header.findIndex((h) => h.startsWith(name))] || "";
      const finding = col("finding");
      if (!finding) continue;
      findings.push({ project: p, mission, finding, fix: col("fix"), p: (col("p").match(/P[123]/) || [""])[0], kind: col("kind"), status: col("status") });
    }
  }
}
if (!missions.length) { console.log(`learn: no retros under ${root}/*/retros yet`); process.exit(0); }

// --- recurrence ----------------------------------------------------------------
const STOP = new Set("about after again before being cannot could every first found their there these thing those though under until where which while would without whole should still".split(" "));
const words = (s) => new Set(String(s).toLowerCase().replace(/`[^`]*`/g, (c) => c.replace(/[^a-z0-9]+/g, " ")).split(/[^a-z0-9]+/).filter((w) => w.length >= 5 && !STOP.has(w)));
const jac = (a, b) => { let i = 0; for (const x of a) if (b.has(x)) i++; return i / (a.size + b.size - i || 1); };
const groups = [];
for (const f of findings) {
  const w = words(`${f.finding} ${f.fix}`);
  const g = groups.find((g) => jac(g.words, w) >= 0.4);
  if (g) { g.items.push(f); for (const x of w) g.words.add(x); } else groups.push({ words: w, items: [f] });
}
const rank = (g) => [new Set(g.items.map((i) => i.project)).size, new Set(g.items.map((i) => `${i.project}/${i.mission}`)).size, g.items.some((i) => i.p === "P1") ? 1 : 0];
groups.sort((a, b) => { const [pa, ma, xa] = rank(a), [pb, mb, xb] = rank(b); return pb - pa || mb - ma || xb - xa; });

// --- output --------------------------------------------------------------------
const L = [];
const k = (n) => (n == null ? "-" : n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(0)}k` : String(n));
L.push(`# What the missions taught (${missions.length} missions, ${new Set(missions.map((m) => m.project)).size} projects)`, "");
L.push("## Missions", "", "| Project | Mission | Tickets | Rounds | First pass | Decisions (target 5) | Runs | Tokens in | Cycle h |", "|---|---|---|---|---|---|---|---|---|");
for (const { project, mission, metrics: m } of missions)
  L.push(`| ${project} | ${mission} | ${m.tickets ?? "-"} | ${m.rounds ?? "-"} | ${m.firstPass ?? "-"}/${m.reviewed ?? "-"} | ${m.decisions ?? "-"} | ${m.runs ?? "-"} | ${k(m.tokensIn)} | ${m.cycleHours ?? "-"} |`);
L.push("", "## Findings, recurring first", "");
for (const g of groups) {
  const [np, nm] = rank(g), top = g.items.find((i) => i.p === "P1") || g.items[0];
  L.push(`- **${top.p || "P?"}${top.kind ? ` · ${top.kind}` : ""}** · seen in ${nm} mission(s), ${np} project(s): ${top.finding}`);
  if (top.fix) L.push(`  - fix proposed: ${top.fix}`);
  for (const o of g.items.filter((i) => i !== top)) L.push(`  - also (${o.project}/${o.mission}): ${o.finding}`);
}
let out = L.join("\n") + "\n";

if (!raw) {
  const pIdx = new Map(projects.map((p, i) => [p, `<project-${i + 1}>`]));
  const mIdx = new Map([...new Set(missions.map((m) => m.mission))].map((m, i) => [m, `<mission-${i + 1}>`]));
  const terms = read(join(homedir(), ".pi-factory", "scrub-terms")).split("\n").map((t) => t.trim()).filter((t) => t && !t.startsWith("#"));
  let user = ""; try { user = execFileSync("git", ["config", "user.name"], { encoding: "utf8" }).trim(); } catch {}
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const names = [...[...pIdx.keys()].map((p) => [p, pIdx.get(p)]), ...[...mIdx.keys()].map((m) => [m, mIdx.get(m)])]
    .sort((a, b) => b[0].length - a[0].length);
  // Project folders are "<repo>[-<subfolder>]": their parts are names too.
  const parts = [...new Set(projects.flatMap((p) => p.split("-").filter((x) => x.length >= 4)))];
  out = out
    .replace(/https?:\/\/[^\s)`|]+/g, "<url>")
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, "<email>")
    .replace(/(\/home|\/Users)\/[^\s/`|]+/g, "<home>").replace(/~\/[^\s`|]*/g, (p) => p.replace(/~\/[^/\s`|]+/, "~/<dir>"))
    .replace(/\b[a-z0-9-]+(\.[a-z0-9-]+){2,}\b/gi, (h) => (/\.(md|mjs|cjs|js|ts|tsx|json|ya?ml|sh|tsv|lock)$/i.test(h) ? h : "<host>"));
  for (const [n, ph] of names) out = out.replace(new RegExp(`(?<![\\w-])${esc(n)}(?![\\w-])`, "g"), ph);
  for (const t of [...terms, ...parts, userInfo().username, user].filter((t) => t && t.length >= 3))
    out = out.replace(new RegExp(esc(t), "gi"), "<term>");
  const left = [...pIdx.keys(), ...mIdx.keys(), ...terms, ...parts].filter((t) => t.length >= 3 && out.toLowerCase().includes(t.toLowerCase()));
  if (left.length) { console.error(`learn: refusing to print: still contains ${left.length} name(s) after scrubbing; run with --raw for your own eyes`); process.exit(3); }
}

if (asJson) console.log(JSON.stringify({ missions: missions.length, groups: groups.length, text: out }, null, 2));
else process.stdout.write(out + (raw ? "\n(--raw: not scrubbed, never share)\n" : "\nScrubbed for sharing; read it before you do.\n"));
