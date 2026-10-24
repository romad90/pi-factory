#!/usr/bin/env node
// Scoring archived runs (D97, P14), called by score.sh.
//   node score.mjs <archive-dir> <scoring-dir> <mission-dir> <scores.tsv> [dimension] [sample]
// For each archived run × dimension that applies to the run's role and falls in
// the sample, asks a judge from another model family than the run, and appends
// one line to scores.tsv: date, run, agent, model, judge, dimension, result, evidence.
// Judge: FACTORY_JUDGE_CMD (a command, split on spaces; FACTORY_JUDGE_BIN for one
// path with spaces) called as `<cmd> <judge-model> <prompt-file>`, printing text
// that must hold `SCORE: pass|fail` and `EVIDENCE: "<quote>"`. Anything else is
// skipped and logged, never guessed. Judge models: FACTORY_JUDGE_MODELS
// (space-separated), else the models of the factory's judge roles.
import { readFileSync, writeFileSync, existsSync, readdirSync, appendFileSync, mkdtempSync } from "node:fs";
import { join, basename, dirname } from "node:path";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";

const [archiveDir, scoringDir, missionDir, scoresFile, onlyDim = "", sampleArg = ""] = process.argv.slice(2);
const here = dirname(new URL(import.meta.url).pathname);
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const field = (t, n) => (t.match(new RegExp(`^\\*\\*${n}:\\*\\*\\s*(.*)$`, "m")) || [])[1]?.trim() ?? "";
const section = (t, n) => (t.split(new RegExp(`^## ${n}\\s*$`, "m"))[1] || "").split(/^## /m)[0].trim();

// Families (D31), as models-lint reads them.
const glob = (p) => new RegExp("^" + p.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$", "i");
let families = [];
try { families = JSON.parse(read(".factory/model-families.json")).families || []; } catch {}
const familyOf = (id) => families.find((f) => glob(f.match).test(id))?.family || "";

let judges = (process.env.FACTORY_JUDGE_MODELS || "").split(/\s+/).filter(Boolean);
if (!judges.length) {
  const r = spawnSync("node", [join(here, "effective-models.mjs")], { encoding: "utf8" });
  const roles = new Set(["factory-reviewer", "factory-review-axis", "factory-validator", "factory-code-steward", "factory-contract-critic"]);
  judges = [...new Set((r.stdout || "").split("\n").map((l) => l.split("\t")).filter((c) => roles.has(c[0]) && c[1] && !/[<>]/.test(c[1])).map((c) => c[1]))];
}
const judgeFor = (model) => judges.find((j) => familyOf(j) && familyOf(j) !== familyOf(model)) || "";

// The factory's own dimensions, then the project's (same name: the project's wins),
// so a project on the installed package (P11) scores without copying them.
const byName = new Map();
for (const d of [join(here, "..", "..", ".factory", "scoring"), scoringDir]) {
  if (!existsSync(d)) continue;
  for (const f of readdirSync(d)) if (f.endsWith(".md") && f !== "README.md") byName.set(f, join(d, f));
}
const dimensions = [...byName.keys()].sort().map((f) => {
  const t = read(byName.get(f));
  return { name: basename(f, ".md"), title: (t.match(/^# (.*)$/m) || [])[1] || f, text: t,
    roles: field(t, "Roles").split(/[,\s]+/).filter(Boolean), sample: Number(field(t, "Sample") || 1) };
}).filter((d) => !onlyDim || d.name === onlyDim);
if (onlyDim && !dimensions.length) { console.error(`score: no dimension '${onlyDim}' in ${scoringDir}`); process.exit(2); }

const done = new Set(read(scoresFile).split("\n").slice(1).filter(Boolean).map((l) => { const c = l.split("\t"); return `${c[1]}\t${c[2]}\t${c[5]}`; }));
const runs = existsSync(archiveDir) ? readdirSync(archiveDir).sort().map((d) => {
  try { return { dir: join(archiveDir, d), ...JSON.parse(read(join(archiveDir, d, "run.json"))) }; } catch { return null; }
}).filter(Boolean) : [];

// Deterministic sample: a run is in when hash(run, dimension) falls under the rate,
// so reruns judge the same runs; --sample n takes the n lowest hashes instead.
const h = (s) => parseInt(createHash("sha256").update(s).digest("hex").slice(0, 8), 16) / 0xffffffff;
const cap = (s, n) => (s.length > n ? `[… ${s.length - n} characters earlier, cut …]\n` + s.slice(-n) : s);

const decisions = read(join(missionDir, "decisions.tsv"));
const work = mkdtempSync(join(tmpdir(), "factory-score-"));
const [judgeBin, ...judgeArgs] = process.env.FACTORY_JUDGE_BIN ? [process.env.FACTORY_JUDGE_BIN]
  : (process.env.FACTORY_JUDGE_CMD || `bash ${join(here, "judge-pi.sh")}`).split(/\s+/).filter(Boolean);
if (!existsSync(scoresFile)) writeFileSync(scoresFile, "date\trun\tagent\tmodel\tjudge\tdimension\tresult\tevidence\n");

let judged = 0, skipped = 0, noJudge = 0;
for (const d of dimensions) {
  let pick = runs.filter((r) => d.roles.includes(r.agent) && !done.has(`${r.run}\t${r.agent}\t${d.name}`));
  pick = sampleArg ? pick.sort((a, b) => h(a.run + d.name) - h(b.run + d.name)).slice(0, Number(sampleArg))
    : pick.filter((r) => h(r.run + d.name) < d.sample);
  for (const r of pick) {
    const judge = judgeFor(r.model);
    if (!judge) { noJudge++; console.error(`score: no judge of another family than ${r.model || "an unknown model"} for ${r.run}`); continue; }
    const prompt = [
      "You judge one run of a software factory's agent against one failure mode. Read only what is below.",
      "Answer with exactly two lines: `SCORE: pass` or `SCORE: fail`, then `EVIDENCE: \"<a short quote from the run that shows it>\"`.",
      "", "# Failure mode", d.text,
      "", `# The run: ${r.agent} on ${r.model}${r.ticket ? `, ticket ${r.ticket}` : ""}`,
      "## The mission's settled decisions (decisions.tsv)", decisions || "(none)",
      "## The brief it got", cap(read(join(r.dir, "brief.md")), 20000),
      "## Its transcript (latest part)", cap(read(join(r.dir, "transcript.jsonl")), 60000),
      "## Its final answer", cap(read(join(r.dir, "output.md")), 8000),
    ].join("\n");
    const pf = join(work, `${r.run}-${d.name}.md`); writeFileSync(pf, prompt);
    const res = spawnSync(judgeBin, [...judgeArgs, judge, pf], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 600000 });
    const out = res.stdout || "";
    const score = (out.match(/^\s*SCORE:\s*(pass|fail)\s*$/im) || [])[1];
    const ev = (out.match(/^\s*EVIDENCE:\s*"(.*)"\s*$/im) || [])[1];
    if (res.status !== 0 || !score || ev === undefined) {
      skipped++; console.error(`score: ${r.run} ${d.name}: judge answer not usable (exit ${res.status}), skipped`); continue;
    }
    appendFileSync(scoresFile, [new Date().toISOString().slice(0, 16).replace("T", " "), r.run, r.agent, r.model, judge, d.name,
      score.toLowerCase(), ev.replace(/[\t\n]/g, " ").slice(0, 300)].join("\t") + "\n");
    judged++;
  }
}
console.log(`score: ${judged} judged, ${skipped} skipped (unusable answer), ${noJudge} without a judge of another family → ${scoresFile}`);
