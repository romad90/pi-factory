// Builds the cockpit snapshot (D90) from status.sh's lines and the mission's
// files. Read-only; every field comes from a file that already exists.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const env = process.env;
const root = env.FACTORY_DIR || ".scratch";
const quietMs = Number(env.QUIET_MIN || 10) * 60_000;
const read = (f, max) => { try { const s = fs.readFileSync(f, "utf8"); return max && s.length > max ? s.slice(-max) : s; } catch { return ""; } };
const exists = (f) => fs.existsSync(f);
const field = (text, name) => (text.match(new RegExp(`^\\*\\*${name}:\\*\\*\\s*(.+)$`, "m")) || [])[1]?.trim() || "";
const firstWord = (s) => s.split(/\s+/)[0] || "";
const heading = (text) => (text.match(/^#\s+(.+)$/m) || [])[1]?.trim() || "";
const tsv = (f) => { const l = read(f).split("\n").filter(Boolean); if (l.length < 2) return []; const h = l[0].split("\t"); return l.slice(1).map((r) => Object.fromEntries(r.split("\t").map((v, i) => [h[i] || `c${i}`, v]))); };
const stripAnsi = (s) => s.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "");

function verdict(file) {
  const t = read(file);
  if (!t) return null;
  // D38: the round is the number of archived copies <stem>.r<N>.md, never what an agent typed.
  const stem = path.basename(file, ".md"), rn = stem.match(/\.r(\d+)$/);
  let copies = 0;
  try { copies = fs.readdirSync(path.dirname(file)).filter((f) => f.startsWith(stem + ".r") && /\.r\d+\.md$/.test(f)).length; } catch {}
  const round = rn ? Number(rn[1]) : copies || Number((t.match(/round (\d+)/) || [])[1]) || null;
  const brief = firstWord(field(t, "Brief"));
  const blocking = t.split("\n").find((l) => /\[blocking\]/.test(l)) || "";
  return {
    result: firstWord(field(t, "Result")), round,
    commit: firstWord(field(t, "Commit")), brief: /^[0-9a-f]{8,}$/.test(brief) ? "" : brief, model: field(t, "Model"),
    blocking: blocking.replace(/^[-*\s]+/, "").slice(0, 300),
    file: path.basename(file),
  };
}

function contract(spec) {
  const out = {};
  const re = /^###\s+(VAL-[A-Z0-9]+-\d{3}):?\s*(.*)$/gm;
  let m; const idx = [];
  while ((m = re.exec(spec))) idx.push({ id: m[1], title: m[2], at: m.index, end: re.lastIndex });
  idx.forEach((a, i) => {
    const body = spec.slice(a.end, i + 1 < idx.length ? idx[i + 1].at : undefined).split(/\n## /)[0];
    const given = body.split("\n").find((l) => /^Given\b/i.test(l.trim())) || "";
    out[a.id] = { title: a.title, kind: firstWord(field(body, "Kind")), given: given.trim() };
  });
  return out;
}

function gitLog(dir) {
  try {
    return execFileSync("git", ["log", "-30", "--format=%h%x09%aI%x09%s", "--", dir], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
      .split("\n").filter(Boolean).map((l) => { const [hash, date, subject] = l.split("\t"); return { hash, date, subject }; });
  } catch { return []; }
}

function workers(mission) {
  const out = [];
  for (const base of (env.RUN_DIRS || "").split(/\s+/).filter(Boolean)) {
    let runs = [];
    try { runs = fs.readdirSync(base); } catch { continue; }
    for (const r of runs) {
      const d = path.join(base, r);
      let logs = [];
      try { logs = fs.readdirSync(d).filter((f) => /^output-\d+\.log$/.test(f)); } catch { continue; }
      for (const f of logs) {
        const p = path.join(d, f); const st = fs.statSync(p);
        if (Date.now() - st.mtimeMs > 3 * 3600_000) continue;
        const head = read(p).slice(0, 8000);
        if (!head.includes(`Mission ${mission}`) && !head.includes(`/${mission}/`)) continue;
        const text = stripAnsi(read(p, 20000));
        const lines = text.split("\n").map((l) => l.trimEnd()).filter((l) => l.trim());
        const done = /\b(completed|finished|Workflow complete)\b/i.test(lines.slice(-3).join(" "));
        out.push({
          run: r, agent: (head.match(/factory-[a-z-]+/) || [""])[0],
          ticket: (head.match(/ticket\s+(\d\d[\w-]*)/i) || [])[1] || "",
          ageSec: Math.round((Date.now() - st.mtimeMs) / 1000), done,
          quiet: !done && Date.now() - st.mtimeMs > quietMs,
          last: lines.slice(-8).map((l) => l.slice(0, 200)),
        });
      }
    }
  }
  return out.sort((a, b) => a.ageSec - b.ageSec).slice(0, 6);
}

function mission(name, lines) {
  const dir = path.join(root, name);
  const spec = read(path.join(dir, "spec.md"));
  const assertions = contract(spec);
  const get = (k) => (lines.find((l) => l[0] === k) || [])[1] || "";
  const decisions = tsv(path.join(dir, "decisions.tsv"));
  const human = decisions.filter((d) => d.kind !== "auto");
  const usage = tsv(path.join(dir, "usage.tsv"));
  const sum = (k) => usage.reduce((s, u) => s + (Number(u[k]) || 0), 0);
  const tickets = lines.filter((l) => l[0] === "T").map(([, name, num, state, round, blockedBy, covers, marker]) => {
    const issue = read(path.join(dir, "issues", `${name}.md`));
    const vdir = path.join(dir, "verdicts");
    let history = [];
    try { history = fs.readdirSync(vdir).filter((f) => f.startsWith(`${name}-code.r`)).sort((a, b) => Number(a.match(/\.r(\d+)\./)[1]) - Number(b.match(/\.r(\d+)\./)[1])).map((f) => verdict(path.join(vdir, f))); } catch {}
    const cov = (covers || "").split(",").filter(Boolean);
    return {
      name, num, state, round: Number(round) || 0, title: heading(issue).replace(/^\d+\s+/, ""),
      size: firstWord(field(issue, "Size")),
      blockedBy: (blockedBy || "").split(",").filter(Boolean), covers: cov,
      assertions: cov.filter((c) => assertions[c]).map((c) => ({ id: c, ...assertions[c] })),
      integrated: marker || "", verdict: verdict(path.join(vdir, `${name}-code.md`)), history,
      journal: read(path.join(dir, "journal", `${name}.md`), 3000),
      stuck: exists(path.join(dir, "state", `${name}.stuck`)),
      staleVerdict: exists(path.join(dir, "state", `${name}.stale-verdict.md`)),
    };
  });
  const live = workers(name);
  const step = get("S"), next = get("N");
  const needs = [];
  if (get("H") === "1") needs.push({ kind: step, text: next });
  const q = read(path.join(dir, "state", "open-question.md"), 1500);
  if (q && step !== "decide") needs.push({ kind: "question", text: q.trim() });
  for (const t of tickets) {
    if (t.state === "escalate" && step !== "escalate") needs.push({ kind: "escalate", ticket: t.name, text: t.verdict?.blocking || "failed its rounds" });
    if (t.stuck) needs.push({ kind: "no-progress", ticket: t.name, text: "the last round failed like the one before (D84)" });
  }
  for (const w of live) if (w.quiet) needs.push({ kind: "quiet", ticket: w.ticket, text: `${w.agent || "a worker"} silent for ${Math.round(w.ageSec / 60)} min` });
  const behavior = verdict(path.join(dir, "verdicts", "behavior.md"));
  const health = verdict(path.join(dir, "verdicts", "health.md"));
  return {
    name, title: heading(spec), intent: firstWord(field(spec, "Intent")), step, next, human: get("H") === "1",
    paused: exists(path.join(dir, "state", "PAUSED.md")),
    contract: { total: Object.keys(assertions).length, approved: /^\*\*Contract approved:\*\*/m.test(spec) },
    counts: tickets.reduce((c, t) => ((c[t.state] = (c[t.state] || 0) + 1), c), { total: tickets.length }),
    tickets, behavior, health,
    interventions: { human: human.length, auto: decisions.length - human.length, target: 5 },
    decisions: decisions.slice(-12).map((d) => ({ date: d.date, ticket: d.ticket, kind: d.kind, question: (d.question || "").slice(0, 200), answer: (d.answer || "").slice(0, 200), who: d.who })),
    runs: tsv(path.join(dir, "runs.tsv")).slice(-12),
    usage: usage.length ? { runs: usage.length, input: sum("input"), output: sum("output"), cacheRead: sum("cache_read"), cost: sum("cost") } : null,
    log: gitLog(dir), workers: live, needs,
  };
}

const groups = []; let cur = null;
for (const raw of fs.readFileSync(0, "utf8").split("\n")) {
  if (!raw) continue;
  const l = raw.split("\t");
  if (l[0] === "M") { cur = { name: l[1], lines: [] }; groups.push(cur); } else if (cur) cur.lines.push(l);
}
const missions = groups.map((g) => mission(g.name, g.lines));
process.stdout.write(JSON.stringify({ generated: new Date().toISOString(), factoryDir: root, missions }, null, 1) + "\n");
