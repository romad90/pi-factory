#!/usr/bin/env node
// Benchmark results (D98): one run's summary, and the comparison of several
// runs the cockpit's Benchmarks view reads. Called by bench.sh.
//
//   node bench-report.mjs summary <results.tsv> <profile.json> <suite> <label> <at> <probe 0|1> <factory version> <briefs hash>
//   node bench-report.mjs print <label.json>
//   node bench-report.mjs compare <bench dir> <label>... [--default <label>] [--strict] [--name <name>] [--min-pass <pct>]
//
// A quality floor keeps cheap failures out of the recommendations: "lowest
// cost" and "most efficient" consider only configurations whose pass rate
// reaches it (default: within 10 points of the default's; --min-pass sets it).
// Below the floor a configuration is shown, marked, never recommended, and
// not on the Pareto line.
//
// A comparison says what it can: each configuration should differ from the
// default by one variable (a role's model, a role's thinking level, or the
// factory itself: version or briefs). More than one, and the result can't say
// which change mattered: a warning, or a refusal with --strict.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const [cmd, ...args] = process.argv.slice(2);
const readJson = (f) => JSON.parse(readFileSync(f, "utf8"));
const pct = (x) => `${Math.round(x * 1000) / 10}%`;
const money = (x) => `$${(Math.round(x * 100) / 100).toFixed(2)}`;
const median = (a) => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };

function tsv(file) {
  const [head, ...rows] = readFileSync(file, "utf8").split("\n").filter(Boolean);
  const h = head.split("\t");
  return rows.map((r) => Object.fromEntries(r.split("\t").map((v, i) => [h[i], v])));
}

function stats(cases) {
  const n = cases.length, passed = cases.filter((c) => c.pass).length;
  const cost = cases.reduce((s, c) => s + c.cost, 0);
  return {
    cases: n, passed, pass_rate: n ? passed / n : 0,
    cost_total: cost, cost_per_trial: n ? cost / n : 0, cost_per_pass: passed ? cost / passed : null,
    median_turns: median(cases.map((c) => c.turns)), mean_seconds: n ? cases.reduce((s, c) => s + c.seconds, 0) / n : 0,
    mean_rounds: n ? cases.reduce((s, c) => s + c.rounds, 0) / n : 0,
  };
}
function breakdown(cases, key) {
  const out = {};
  for (const c of cases) { const k = c[key] || "-"; (out[k] ||= []).push(c); }
  return Object.fromEntries(Object.entries(out).map(([k, v]) => [k, { cases: v.length, passed: v.filter((c) => c.pass).length }]));
}

function summary([file, profile, suite, label, at, probe, version, briefs]) {
  const cases = tsv(file).map((r) => ({
    case: r.case, difficulty: r.difficulty, area: r.area, pass: r.pass === "yes", failed_gate: r.failed_gate === "-" ? null : r.failed_gate,
    turns: Number(r.turns) || 0, tokens: Number(r.tokens) || 0, cost: Number(r.cost) || 0, seconds: Number(r.seconds) || 0, rounds: Number(r.rounds) || 1,
  }));
  const p = readJson(profile);
  const config = Object.fromEntries(Object.entries(p.agents || {}).map(([a, v]) => [a.replace(/^factory-/, ""), { model: v.model || "", thinking: v.thinking || "" }]));
  const out = {
    label, suite, probe: probe === "1", at: at || null, date: new Date().toISOString(),
    factory: { version, briefs }, config, summary: stats(cases),
    breakdown: { difficulty: breakdown(cases, "difficulty"), area: breakdown(cases, "area") }, cases,
  };
  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
}

function print([file]) {
  const r = readJson(file), s = r.summary;
  console.log(`bench: ${r.label} on ${r.suite}${r.probe ? ` (probe at ${String(r.at).slice(0, 12)})` : ""}: ${s.passed}/${s.cases} passed (${pct(s.pass_rate)}), ${money(s.cost_per_trial)} per trial, median ${s.median_turns} turns`);
  for (const c of r.cases.filter((c) => !c.pass)) console.log(`  ✗ ${c.case} (${c.difficulty}): ${c.failed_gate}`);
  console.log(`results: .factory/bench/results/${r.label}.tsv`);
}

// The variables a configuration is defined by, flattened for comparison.
function variables(r) {
  const v = {};
  for (const [role, c] of Object.entries(r.config)) { v[`${role} model`] = c.model; v[`${role} thinking`] = c.thinking; }
  v["factory version"] = r.factory?.version ?? ""; v["factory briefs"] = r.factory?.briefs ?? "";
  return v;
}
function diffVars(a, b) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  return [...keys].filter((k) => (a[k] ?? "") !== (b[k] ?? "")).map((k) => ({ variable: k, default: a[k] ?? "", value: b[k] ?? "" }));
}

function compare([dir, ...rest]) {
  let def = null, strict = false, name = null, minPass = null; const labels = [];
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === "--default") def = rest[++i];
    else if (rest[i] === "--strict") strict = true;
    else if (rest[i] === "--name") name = rest[++i];
    else if (rest[i] === "--min-pass") { minPass = Number(rest[++i]); if (!(minPass >= 0 && minPass <= 100)) { console.error("--min-pass: a percentage, 0 to 100"); process.exit(2); } }
    else labels.push(rest[i]);
  }
  if (labels.length < 2) { console.error("compare needs at least two labels"); process.exit(2); }
  const runs = labels.map((l) => { const f = join(dir, "results", `${l}.json`); if (!existsSync(f)) { console.error(`no results for ${l} (${f})`); process.exit(2); } return readJson(f); });
  def ??= labels[0];
  const d = runs.find((r) => r.label === def);
  if (!d) { console.error(`--default ${def} is not among the labels`); process.exit(2); }
  const suites = new Set(runs.map((r) => r.suite));
  const warnings = [];
  if (suites.size > 1) warnings.push(`the runs are on different suites (${[...suites].join(", ")}): pass rates are not comparable`);
  const caseSets = runs.map((r) => r.cases.map((c) => c.case).sort().join(","));
  if (new Set(caseSets).size > 1) warnings.push("the runs did not replay the same cases");
  const dv = variables(d);
  const configs = runs.map((r) => {
    const diff = r.label === def ? [] : diffVars(dv, variables(r));
    if (r.label !== def && diff.length > 1) warnings.push(`${r.label} differs from ${def} by ${diff.length} variables (${diff.map((x) => x.variable).join(", ")}): the result can't say which one mattered`);
    if (r.label !== def && diff.length === 0) warnings.push(`${r.label} has the same configuration as ${def}: a repeat, useful to see the noise`);
    return { label: r.label, diff, ...r.summary };
  });
  // The quality floor: cheap is only worth recommending if it still passes.
  const floor = minPass != null ? minPass / 100 : Math.max(0, d.summary.pass_rate - 0.10);
  for (const c of configs) c.below_floor = c.pass_rate < floor - 1e-9;
  const qualified = configs.filter((c) => !c.below_floor);
  // Pareto, among configurations above the floor: no other passes at least as
  // often for at most the cost, strictly better on one.
  for (const c of configs) {
    c.pareto = !c.below_floor && !qualified.some((o) => o !== c && o.pass_rate >= c.pass_rate && o.cost_per_trial <= c.cost_per_trial
      && (o.pass_rate > c.pass_rate || o.cost_per_trial < c.cost_per_trial));
  }
  const byQuality = [...configs].sort((a, b) => b.pass_rate - a.pass_rate || a.cost_per_trial - b.cost_per_trial)[0];
  const eff = (c) => (c.cost_per_trial > 0 ? c.pass_rate / c.cost_per_trial : (c.pass_rate > 0 ? Infinity : 0));
  const byEfficiency = qualified.length ? [...qualified].sort((a, b) => eff(b) - eff(a) || b.pass_rate - a.pass_rate)[0] : null;
  const byCost = qualified.length ? [...qualified].sort((a, b) => a.cost_per_trial - b.cost_per_trial || b.pass_rate - a.pass_rate)[0] : null;
  const rec = (kind, c) => c ? { kind, label: c.label, pass_rate: c.pass_rate, cost_per_trial: c.cost_per_trial }
    : { kind, label: null, note: `no configuration reaches the quality floor (${pct(floor)})` };
  const recommendations = [rec("highest quality", byQuality), rec("most efficient", byEfficiency), rec("lowest cost", byCost)];
  const below = configs.filter((c) => c.below_floor).map((c) => `${c.label} (${pct(c.pass_rate)})`);
  const n = runs[0].summary.cases;
  const changed = configs.filter((c) => c.label !== def && c.diff.length === 1).map((c) => `${c.label} (${c.diff[0].variable}: ${c.diff[0].value || "unset"})`);
  const text = `${configs.length} configurations on suite ${[...suites].join("+")}, ${n} cases each, against the default ${def}` +
    (changed.length ? `; one variable changed in ${changed.join(", ")}` : "") + `. ` +
    `${byQuality.label} passes most (${pct(byQuality.pass_rate)}, ${money(byQuality.cost_per_trial)} per trial). ` +
    (!byEfficiency ? `No configuration reaches the quality floor of ${pct(floor)}, so none is recommended on cost. `
      : (byEfficiency.label === byQuality.label ? `It is also the most efficient` : `${byEfficiency.label} gives the most passes per unit of cost (${pct(byEfficiency.pass_rate)} at ${money(byEfficiency.cost_per_trial)} per trial)`) +
        (byCost.label === byEfficiency.label ? `, and the cheapest above the quality floor of ${pct(floor)}. ` : `; ${byCost.label} is the cheapest above the quality floor of ${pct(floor)} (${money(byCost.cost_per_trial)} per trial, ${pct(byCost.pass_rate)}). `)) +
    (below.length ? `Below the floor, never recommended: ${below.join(", ")}.` : "");
  const tiers = ["easy", "medium", "hard", "extra-hard"];
  const table = (key, order) => {
    const keys = order ?? [...new Set(runs.flatMap((r) => Object.keys(r.breakdown[key])))].sort();
    return keys.filter((k) => runs.some((r) => r.breakdown[key][k])).map((k) => ({
      [key]: k, ...Object.fromEntries(runs.map((r) => { const b = r.breakdown[key][k]; return [r.label, b ? `${b.passed}/${b.cases}` : "-"]; })),
    }));
  };
  const out = {
    name: name ?? labels.join("-vs-"), date: new Date().toISOString(), default: def, suite: [...suites].join("+"), floor,
    summary: text, recommendations, warnings,
    axes: ["pass_rate", "cost_per_trial", "median_turns", "mean_seconds", "mean_rounds"],
    points: configs.map((c) => ({ label: c.label, pass_rate: c.pass_rate, cost_per_trial: c.cost_per_trial, median_turns: c.median_turns,
      mean_seconds: c.mean_seconds, mean_rounds: c.mean_rounds, pareto: c.pareto, below_floor: c.below_floor, diff: c.diff })),
    breakdown: { difficulty: table("difficulty", tiers), area: table("area") },
  };
  const refused = strict && warnings.some((w) => /variables/.test(w));
  if (refused) {
    for (const w of warnings) console.log(`⚠ ${w}`);
    console.log("compare --strict: refused, nothing written; compare configurations that differ by one variable");
    process.exit(1);
  }
  mkdirSync(join(dir, "compare"), { recursive: true });
  const file = join(dir, "compare", `${out.name.replace(/[^A-Za-z0-9._-]/g, "_")}.json`);
  writeFileSync(file, JSON.stringify(out, null, 2) + "\n");
  // Answer first, then the numbers.
  console.log(text);
  console.log("");
  for (const r of recommendations) console.log(r.label ? `${r.kind.padEnd(16)} ${r.label}  ${pct(r.pass_rate)}  ${money(r.cost_per_trial)}/trial` : `${r.kind.padEnd(16)} none: ${r.note}`);
  for (const w of warnings) console.log(`⚠ ${w}`);
  console.log("");
  console.log(["config", "pass", "cost/trial", "turns", "seconds", "pareto"].join("\t"));
  for (const c of configs) console.log([c.label + (c.label === def ? " (default)" : ""), pct(c.pass_rate), money(c.cost_per_trial), c.median_turns, Math.round(c.mean_seconds), c.below_floor ? "below the floor" : c.pareto ? "yes" : ""].join("\t"));
  for (const key of ["difficulty", "area"]) {
    const rows = out.breakdown[key]; if (!rows.length || (rows.length === 1 && rows[0][key] === "-")) continue;
    console.log(""); console.log([key, ...labels].join("\t"));
    for (const row of rows) console.log([row[key], ...labels.map((l) => row[l])].join("\t"));
  }
  console.log(""); console.log(`compare: ${file}`);
}

// --- paired: the same cases under two arms, repeats pooled (P20: is a change real?) ---
// node bench-report.mjs paired <bench dir> --a <label,label…> --b <label,label…> [--seed N] [--iters N]
// Per case: mean tokens and turns per arm over its repeats, pass by majority.
// Paired deltas (b − a), their median with a percentile bootstrap 95% CI
// (seeded: the same inputs give the same interval), and McNemar's exact test
// on the cases whose majority pass differs. A total over different tickets
// says nothing; this compares like with like.
function paired(argv) {
  const [dir] = argv, opt = (n) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : null; };
  const A = (opt("--a") || "").split(",").filter(Boolean), B = (opt("--b") || "").split(",").filter(Boolean);
  if (!dir || !A.length || !B.length) { console.error("usage: paired <bench dir> --a l1,l2 --b l1,l2 [--seed N] [--iters N]"); process.exit(2); }
  let seed = Number(opt("--seed") || 7) >>> 0; const iters = Number(opt("--iters") || 2000);
  const rnd = () => { seed = (seed + 0x6D2B79F5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const arm = (labels) => {
    const by = {};
    for (const l of labels) for (const r of tsv(join(dir, "results", `${l}.tsv`))) {
      const c = (by[r.case] ||= { tokens: [], turns: [], pass: [] });
      c.tokens.push(Number(r.tokens) || 0); c.turns.push(Number(r.turns) || 0); c.pass.push(r.pass === "yes");
    }
    return by;
  };
  const a = arm(A), b = arm(B), mean = (x) => x.reduce((s, v) => s + v, 0) / (x.length || 1);
  const cases = Object.keys(a).filter((k) => b[k]).sort();
  if (!cases.length) { console.error("paired: no case ran in both arms"); process.exit(1); }
  const rows = cases.map((k) => ({ case: k, runs: [a[k].pass.length, b[k].pass.length],
    tokens: [mean(a[k].tokens), mean(b[k].tokens)], turns: [mean(a[k].turns), mean(b[k].turns)],
    pass: [mean(a[k].pass.map(Number)) > 0.5, mean(b[k].pass.map(Number)) > 0.5] }));
  const ci = (d) => {
    const meds = [];
    for (let i = 0; i < iters; i++) meds.push(median(d.map(() => d[Math.floor(rnd() * d.length)])));
    meds.sort((x, y) => x - y);
    return [meds[Math.floor(0.025 * iters)], meds[Math.min(iters - 1, Math.floor(0.975 * iters))]];
  };
  const stat = (key) => { const d = rows.map((r) => r[key][1] - r[key][0]); const [lo, hi] = ci(d);
    return { median_a: median(rows.map((r) => r[key][0])), median_b: median(rows.map((r) => r[key][1])), median_delta: median(d), ci95: [lo, hi], excludes_zero: lo > 0 || hi < 0 }; };
  // McNemar exact (two-sided binomial on discordant pairs).
  const bOnly = rows.filter((r) => !r.pass[0] && r.pass[1]).length, aOnly = rows.filter((r) => r.pass[0] && !r.pass[1]).length, n = aOnly + bOnly;
  const choose = (n, k) => { let c = 1; for (let i = 1; i <= k; i++) c = (c * (n - k + i)) / i; return c; };
  let p = 1; if (n) { const k = Math.min(aOnly, bOnly); let tail = 0; for (let i = 0; i <= k; i++) tail += choose(n, i); p = Math.min(1, 2 * tail / 2 ** n); }
  const out = { a: A, b: B, cases: rows.length, tokens: stat("tokens"), turns: stat("turns"),
    pass: { a: rows.filter((r) => r.pass[0]).length, b: rows.filter((r) => r.pass[1]).length, only_a: aOnly, only_b: bOnly, mcnemar_p: Number(p.toFixed(4)) },
    rows, note: rows.length < 5 ? "fewer than 5 paired cases: read the rows, not the interval" : null };
  if (argv.includes("--json")) { process.stdout.write(JSON.stringify(out, null, 2) + "\n"); return; }
  const k = (v) => (Math.abs(v) >= 1000 ? `${(v / 1000).toFixed(1)}k` : String(Math.round(v)));
  console.log(`paired: ${rows.length} cases, a = ${A.join("+")}, b = ${B.join("+")}`);
  for (const key of ["tokens", "turns"]) { const t = out[key];
    console.log(`  ${key}: median ${k(t.median_a)} → ${k(t.median_b)}, paired median change ${k(t.median_delta)} (95% CI ${k(t.ci95[0])} to ${k(t.ci95[1])})${t.excludes_zero ? "" : ": the interval includes no change"}`); }
  console.log(`  pass: a ${out.pass.a}/${rows.length}, b ${out.pass.b}/${rows.length}; only a ${aOnly}, only b ${bOnly}; McNemar p = ${out.pass.mcnemar_p}`);
  if (out.note) console.log(`  note: ${out.note}`);
  for (const r of rows) console.log(`  ${r.case.padEnd(28)} tokens ${k(r.tokens[0])} → ${k(r.tokens[1])}  turns ${r.turns[0].toFixed(1)} → ${r.turns[1].toFixed(1)}  pass ${r.pass[0] ? "yes" : "no"} → ${r.pass[1] ? "yes" : "no"}  (${r.runs[0]}+${r.runs[1]} runs)`);
}

if (cmd === "summary") summary(args);
else if (cmd === "paired") paired(args);
else if (cmd === "print") print(args);
else if (cmd === "compare") compare(args);
else { console.error("usage: bench-report.mjs summary|print|compare ..."); process.exit(2); }
