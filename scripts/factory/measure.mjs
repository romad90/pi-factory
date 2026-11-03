#!/usr/bin/env node
// measures.md from the raw inputs measure.sh gathered. Every row has an id
// ([M-n]) the architect's strategy must cite. No model, no estimate: what
// isn't measured is written as missing.
import { readFileSync, writeFileSync, existsSync, statSync, readdirSync } from "node:fs";
import { join, basename, dirname, extname } from "node:path";

const [out, job, tmp, rcArg, secsArg, testCmd, mutationPath, firstCommit, yearCommits, scratch] = process.argv.slice(2);
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const rows = [];
const add = (what, value) => { rows.push([`M-${rows.length + 1}`, what, value]); };
const cell = (s) => String(s).replace(/\|/g, "\\|").replace(/\s+/g, " ").trim();

// Tests.
const rc = Number(rcArg);
if (rc < 0) add("tests", "no test command configured (FACTORY_TEST_CMD): nothing pins behavior");
else {
  const summary = read(join(tmp, "tests.log")).split("\n").filter((l) => /\b(tests?|suites?|passed|failed|passing|failing|ok|error)\b/i.test(l) && l.length < 160).slice(-3).join("; ");
  add("tests", `\`${testCmd}\` exit ${rc} in ${secsArg}s${summary ? `: ${summary}` : ""}`);
}
add("history", `first commit ${firstCommit || "unknown"}; ${yearCommits} commit(s) in the past year`);

// Files: health flags, churn, importers, mutation.
const flags = new Map();
const flag = (f, k) => { if (!f) return; const e = flags.get(f) || {}; e[k] = (e[k] || 0) + 1; flags.set(f, e); };
for (const l of read(join(tmp, "health.txt")).split("\n")) {
  let m;
  if ((m = l.match(/^deep\s+(\S+?):\d+/))) flag(m[1], "deep");
  else if ((m = l.match(/^large\s+(\S+?)(:\d+)?(\s|$)/))) flag(m[1], "large");
  else if ((m = l.match(/^dup\s+(\S+?):\d+\s*=\s*(\S+?):\d+/))) { flag(m[1], "dup"); flag(m[2], "dup"); }
}
const churn = new Map();
for (const f of read(join(tmp, "churn.txt")).split("\n").filter(Boolean)) churn.set(f, (churn.get(f) || 0) + 1);
const generated = (f) => /(^|\/)(types|dist|build|node_modules|coverage|reports)\//.test(f) || /\.d\.ts$/.test(f);
const isTest = (f) => /(^|\/)(test|tests|__tests__|spec)\//.test(f) || /\.(test|spec)\.[a-z]+$/.test(f);
const tracked = read(join(tmp, "files.txt")).split("\n").filter(Boolean);
const code = tracked.filter((f) => /\.(ts|tsx|js|jsx|mjs|cjs|py|go|rb|java|kt|rs|php|cs)$/.test(f) && !generated(f));
const candidates = [...new Set([...flags.keys(), ...[...churn.keys()].filter((f) => code.includes(f))])]
  .filter((f) => code.includes(f) && !isTest(f) && !f.startsWith(".scratch/") && !f.startsWith("scripts/factory/")).sort();

// Importers: files whose import or require names the file (index files by their folder).
const texts = new Map(code.map((f) => [f, read(f)]));
const importers = (f) => {
  const stem = basename(f, extname(f)) === "index" ? basename(dirname(f)) : basename(f, extname(f));
  const re = new RegExp(`(from\\s+|require\\(|import\\s*\\(|import\\s+)['"][^'"]*\\b${stem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(/index)?(\\.[a-z]+)?['"]`);
  let n = 0;
  for (const [g, t] of texts) if (g !== f && re.test(t)) n++;
  return n;
};

// Mutation scores (Stryker's mutation-testing-report-schema).
let mutation = null, mutationNote = `no mutation report at ${mutationPath}: test strength is not measured`;
if (existsSync(mutationPath)) {
  try {
    const r = JSON.parse(read(mutationPath)), when = statSync(mutationPath).mtime.toISOString().slice(0, 10);
    mutation = new Map();
    for (const [f, v] of Object.entries(r.files || {})) {
      const c = {};
      for (const m of v.mutants || []) c[m.status] = (c[m.status] || 0) + 1;
      const detected = (c.Killed || 0) + (c.Timeout || 0);
      const valid = (v.mutants || []).length - (c.CompileError || 0) - (c.RuntimeError || 0) - (c.Ignored || 0);
      mutation.set(f.replace(/^\.\//, ""), { score: valid ? Math.round((1000 * detected) / valid) / 10 : null, survived: c.Survived || 0, nocov: c.NoCoverage || 0 });
    }
    mutationNote = `mutation report ${mutationPath} of ${when}, ${mutation.size} file(s); files not in it are not measured`;
  } catch { mutationNote = `mutation report ${mutationPath} unreadable`; }
}
add("test strength", mutationNote);

const fileRows = [];
for (const f of candidates) {
  const fl = flags.get(f) || {}, mu = mutation && (mutation.get(f) || [...mutation.entries()].find(([k]) => k.endsWith(`/${f}`) || f.endsWith(`/${k}`))?.[1]);
  const parts = [
    fl.deep ? `deep ×${fl.deep}` : "", fl.large ? "large" : "", fl.dup ? `duplicated ×${fl.dup}` : "",
    `${churn.get(f) || 0} change(s) in a year`, `${importers(f)} importer(s)`,
    mu ? `mutation ${mu.score ?? "-"}% (${mu.survived} survived, ${mu.nocov} not covered)` : mutation ? "mutation: not in the report" : "",
  ].filter(Boolean);
  fileRows.push([f, parts.join(", ")]);
}
for (const [f, v] of fileRows) add(`file ${f}`, v);

const api = tracked.filter((f) => /^etc\/.*\.api\.md$/.test(f) || /\.api\.md$/.test(f));
add("public surface", api.length ? `committed API report: ${api.join(", ")} (a change shows as a diff)` : "no committed API report: a change to the public surface would not be seen by a script");

if (existsSync(scratch)) for (const m of readdirSync(scratch).sort()) {
  const spec = join(scratch, m, "spec.md");
  if (m === job || !existsSync(spec)) continue;
  const s = read(spec), intent = (s.match(/^\*\*Intent:\*\*\s*(\S+)/m) || [])[1] || "?";
  const b = read(join(scratch, m, "verdicts", "behavior.md")), result = (b.match(/^\*\*Result:\*\*\s*(\S+)/m) || [])[1];
  add(`mission ${m}`, `intent ${intent}; ${result ? `behavior ${result}` : "not validated"}${existsSync(join(scratch, m, "mr.url")) ? "; MR opened" : ""} (its spec is dated intent)`);
}

const L = [`# Measures: ${job}`, "", `Computed by scripts/factory/measure.sh on ${new Date().toISOString().slice(0, 10)} at ${process.env.MEASURE_HEAD || "HEAD"}. No model. Cite the ids.`, "", "| Id | What | Value |", "|---|---|---|"];
for (const [id, what, value] of rows) L.push(`| ${id} | ${cell(what)} | ${cell(value)} |`);
L.push("", `Files listed: those the health check flags or the past year changed (${fileRows.length}). Generated files and tests are left out.`);
writeFileSync(out, L.join("\n") + "\n");
