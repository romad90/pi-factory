// Builds the cockpit snapshot (D90) from status.sh's lines and the mission's
// files. Read-only; every field comes from a file that already exists.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { parseCritique, toContract } from "./cockpit-contract.mjs";
import { replay } from "./run-detail.mjs";
import { parseContract } from "./gate-doc.mjs";

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

// The contract's assertions by id (gate-doc.mjs parses "- **Given:** …" fields, D130).
function contract(spec) {
  return Object.fromEntries(parseContract(spec || "").assertions.map((a) => [a.id, { title: a.title, kind: a.kind, given: a.given }]));
}

const git = (args) => { try { return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 32 << 20 }); } catch { return ""; } };
const isCheckpoint = (subject, trailer) => /checkpoint/i.test(trailer || "") || /^chore\(factory\): \S+ state$/.test(subject);

// The progress log is events that mean something (P10): integrations,
// verdicts and gate results (their archived copies, D38), decisions, stuck and
// stale markers, questions. Checkpoint commits only carry those files: they are
// never listed themselves (trailer "Factory-Script: checkpoint", else subject).
function events(name, dir, prefix) {
  const ev = [];
  const fmt = "--format=@@%h%x09%aI%x09%s%x09%(trailers:key=Factory-Script,valueonly,separator=%x2C)";
  for (const l of git(["log", "-400", fmt]).split("\n")) {
    if (!l.startsWith("@@")) continue;
    const [hash, date, subject, trailer] = l.slice(2).split("\t");
    const m = subject.match(new RegExp(`^(feat|fix|test|docs|refactor|perf|style)\\(${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\): (.+)$`));
    if (m && !isCheckpoint(subject, trailer)) ev.push({ date, kind: "integrated", ticket: m[2].trim(), text: `${m[1]} commit ${hash}`, ok: true });
  }
  let cur = null;
  for (const l of git(["log", "-300", "--name-status", "--no-renames", fmt, "--", dir]).split("\n")) {
    if (l.startsWith("@@")) { const [, date] = l.slice(2).split("\t"); cur = date; continue; }
    const m = l.match(/^A\t(.+)$/); if (!m || !cur) continue;
    const base = prefix + dir.replace(/^\.\//, "") + "/";
    if (!m[1].startsWith(base)) continue;
    const rel = m[1].slice(base.length);
    let x;
    if ((x = rel.match(/^verdicts\/(.+)-code\.r(\d+)\.md$/))) {
      const v = verdict(path.join(dir, rel)) || {};
      const pass = v.result === "PASS";
      ev.push({ date: cur, kind: "verdict", ticket: x[1], ok: pass, text: `round ${x[2]} ${v.result || "?"}${v.brief ? " · " + v.brief : ""}${!pass && v.blocking ? " — " + v.blocking : ""}` });
    } else if ((x = rel.match(/^verdicts\/(behavior|health)\.r(\d+)\.md$/))) {
      const v = verdict(path.join(dir, rel)) || {};
      ev.push({ date: cur, kind: "gate", ticket: "", ok: v.result === "PASS", text: `${x[1] === "behavior" ? "behavior (G4)" : "code steward (G5)"} round ${x[2]} ${v.result || "?"}${v.result !== "PASS" && v.blocking ? " — " + v.blocking : ""}` });
    } else if ((x = rel.match(/^state\/(.+)\.stuck$/))) ev.push({ date: cur, kind: "escalated", ticket: x[1], ok: false, text: "no progress: failed like the round before (D84)" });
    else if ((x = rel.match(/^state\/(.+)\.stale-verdict\.md$/))) ev.push({ date: cur, kind: "stale", ticket: x[1], ok: null, text: "verdict on an older commit set aside (D81)" });
    else if (rel === "state/open-question.md") ev.push({ date: cur, kind: "question", ticket: "", ok: null, text: "a question waits for the human" });
    else if (rel === "health/report.md") ev.push({ date: cur, kind: "gate", ticket: "", ok: null, text: "health ratchet ran (G5)" });
  }
  // Decisions, at the time each row was committed.
  let when = null;
  for (const l of git(["log", "-200", "-p", "--unified=0", "--format=@@%aI", "--", path.join(dir, "decisions.tsv")]).split("\n")) {
    if (l.startsWith("@@") && !l.startsWith("@@ ")) { when = l.slice(2); continue; }
    if (!when || !l.startsWith("+") || l.startsWith("+++") || l.startsWith("+date\t")) continue;
    const [, ticket, kind, question, answer, , who] = l.slice(1).split("\t");
    if (!kind) continue;
    const auto = kind === "auto";
    ev.push({ date: when, kind: auto ? "auto-answer" : "decision", ticket: ticket === "-" ? "" : ticket, ok: null, human: !auto,
      text: `${auto ? "" : kind + ": "}${(question || "").slice(0, 140)} → ${(answer || "").slice(0, 160)}${who && !auto ? " (" + who + ")" : ""}` });
  }
  ev.sort((a, b) => (a.date < b.date ? 1 : -1));
  if (ev.length) return ev.slice(0, 60);
  // Nothing recorded yet: the mission's own commits, checkpoints left out.
  return git(["log", "-30", fmt, "--", dir]).split("\n").filter((l) => l.startsWith("@@")).map((l) => l.slice(2).split("\t"))
    .filter(([, , subject, trailer]) => !isCheckpoint(subject, trailer)).map(([hash, date, subject]) => ({ date, kind: "commit", ticket: "", ok: null, text: `${subject} (${hash})` }));
}

function workers(mission) {
  const out = [];
  // A run whose log stopped before the mission's last commit was collected by
  // the lead: finished, not quiet (a ticket writer done for an hour is not stuck).
  let lastCommitMs = 0;
  try { lastCommitMs = 1000 * Number(git(["log", "-1", "--format=%ct", "--", path.join(root, mission)]).trim() || 0); } catch {}
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
        const done = /\b(completed|finished|Workflow complete)\b/i.test(lines.slice(-3).join(" ")) || (lastCommitMs > 0 && st.mtimeMs < lastCommitMs);
        out.push({
          run: r, agent: (head.match(/factory-[a-z-]+/) || [""])[0],
          ticket: (head.match(/ticket\s+(\d\d[\w-]*)/i) || [])[1] || "",
          ageSec: Math.round((Date.now() - st.mtimeMs) / 1000), done,
          quiet: !done && Date.now() - st.mtimeMs > quietMs,
          last: lines.slice(-60).map((l) => l.slice(0, 400)),   // the box scrolls; the tail is enough to follow a run
        });
      }
    }
  }
  return out.sort((a, b) => a.ageSec - b.ageSec).slice(0, 6);
}

// D119: the mission's runs by role, from the run archive (archive.sh collect):
// start, end, model, cost, tool calls and the guard's refusals with their time.
// Never a transcript: run.json carries the counts, so the snapshot stays cheap
// at 50 missions.
const archiveRoot = env.FACTORY_ARCHIVE_DIR || (() => { const g = git(["rev-parse", "--path-format=absolute", "--git-common-dir"]).trim(); return g ? path.join(g, "pi-factory", "archive") : ""; })();
function timeline(name) {
  const dir = archiveRoot && path.join(archiveRoot, name);
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return []; }
  const runs = [];
  for (const d of names) {
    let j; try { j = JSON.parse(read(path.join(dir, d, "run.json"))); } catch { continue; }
    if (!j || !j.date) continue;
    // archive.mjs writes start (from the transcript); older records only the time first seen.
    const dur = Number(j.durationMs) || 0;
    const start = j.start ? Date.parse(j.start) : Date.parse(j.date) - dur, end = j.start ? start + dur : Date.parse(j.date);
    if (Number.isNaN(end) || Number.isNaN(start)) continue;
    runs.push({
      run: String(j.run || d).slice(0, 8), dir: d, role: String(j.agent || "?").replace(/^factory-/, ""), model: j.model || "", ticket: j.ticket || "",
      start: new Date(start).toISOString(), end: new Date(end).toISOString(), ms: end - start,
      cost: j.usage?.cost || 0, input: j.usage?.input || 0, output: j.usage?.output || 0,
      calls: typeof j.calls === "number" ? j.calls : null, result: j.outcome?.result || (j.outcome?.integrated ? "integrated" : ""),
      refused: (Array.isArray(j.guard) ? j.guard : []).map((g) => ({ at: g.date || "", rule: g.rule || "", tool: g.tool || "", input: String(g.input || "").slice(0, 300), today: replay(g).today })),
    });
  }
  return runs.sort((a, b) => a.start.localeCompare(b.start)).slice(-200);
}

// The contract critic's findings (contract-critique.md), so the G1 card shows
// them instead of a file name, and whether the critique was written after the
// contract it judges (the lead couldn't tell, deps-node-22).
function critique(dir) {
  const f = path.join(dir, "contract-critique.md"), t = read(f);
  if (!t) return null;
  const mtime = (p) => { try { return fs.statSync(p).mtimeMs; } catch { return 0; } };
  let amendments = 0; try { amendments = fs.readdirSync(path.join(dir, "amendments")).filter((x) => x.endsWith(".md")).length; } catch {}
  return { ...parseCritique(t), round: amendments + 1, at: new Date(mtime(f)).toISOString(), afterContract: mtime(f) >= mtime(path.join(dir, "spec.md")) };
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
    name, title: heading(spec), intent: firstWord(field(spec, "Intent")), step, next, human: get("H") === "1", otherBranch: get("O"),
    paused: exists(path.join(dir, "state", "PAUSED.md")),
    question: q.trim(), critique: critique(dir),
    mr: read(path.join(dir, "mr.url")).trim().split("\n")[0] || "",   // D119: a mission with mr.url is closed, whatever step it showed
    contract: { total: Object.keys(assertions).length, approved: (() => {   // D101: the line and its human.sh row
      const d = (spec.match(/^\*\*Contract approved:\*\* (\d{4}-\d{2}-\d{2})/m) || [])[1];
      const last = decisions.filter((r) => r.kind === "approve" || r.kind === "amend").pop();
      return !!d && last?.kind === "approve" && last.date === d; })() },
    counts: tickets.reduce((c, t) => ((c[t.state] = (c[t.state] || 0) + 1), c), { total: tickets.length }),
    tickets, behavior, health,
    interventions: { human: human.length, auto: decisions.length - human.length, target: 5 },
    decisions: decisions.slice(-12).map((d) => ({ date: d.date, ticket: d.ticket, kind: d.kind, question: (d.question || "").slice(0, 200), answer: (d.answer || "").slice(0, 200), who: d.who })),
    runs: tsv(path.join(dir, "runs.tsv")).slice(-12),
    usage: usage.length ? { runs: usage.length, input: sum("input"), output: sum("output"), cacheRead: sum("cache_read"), cost: sum("cost") } : null,
    log: events(name, dir, (git(["rev-parse", "--show-prefix"]).trim())), workers: live, needs,
    timeline: timeline(name),
  };
}

const groups = []; let cur = null;
for (const raw of fs.readFileSync(0, "utf8").split("\n")) {
  if (!raw) continue;
  const l = raw.split("\t");
  if (l[0] === "M") { cur = { name: l[1], lines: [] }; groups.push(cur); } else if (cur) cur.lines.push(l);
}
const missions = groups.map((g) => mission(g.name, g.lines));
// D97: totals across missions (metrics.sh --all --json), when status.sh passes them.
let factory = null;
try { if (env.METRICS) factory = JSON.parse(read(env.METRICS)).total || null; } catch {}
// D98: the factory engineer's benchmarks, newest comparison first (bench.sh compare).
// D122: the causes the learning loop classified (taxonomy.tsv, private to the
// machine), for the factory engineer's Health page. Only with --all.
let causes = [];
if (env.ALL) {
  const learn = env.FACTORY_LEARN_DIR || (archiveRoot ? path.join(path.dirname(archiveRoot), "learn") : "");
  causes = tsv(path.join(learn, "taxonomy.tsv")).map((r) => ({ id: r.id || "", when: r.when_utc || "", mission: r.mission || "", event: r.event || "",
    cost: r.cost || "", class: r.cause_class || "", cause: r.cause || "", status: r.status || "", evidence: r.evidence || "" }));
}
const benchDir = env.FACTORY_BENCH_DIR || ".factory/bench";
let bench = [];
try {
  bench = fs.readdirSync(path.join(benchDir, "compare")).filter((f) => f.endsWith(".json"))
    .map((f) => { try { return JSON.parse(read(path.join(benchDir, "compare", f))); } catch { return null; } })
    .filter(Boolean).sort((a, b) => String(b.date).localeCompare(String(a.date))).slice(0, 10);
} catch {}
// D119: every view reads one versioned contract, the same here and in a cloud deployment.
process.stdout.write(JSON.stringify(toContract({ generated: new Date().toISOString(), factoryDir: root, project: git(["rev-parse", "--show-toplevel"]).trim() || process.cwd(), factory, missions, bench, causes }), null, 1) + "\n");
