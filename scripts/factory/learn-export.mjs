#!/usr/bin/env node
// Lessons from a machine whose records must stay there (P27, D115). The
// learning loop (P26) reads raw records; on a work machine those records hold
// the company's hosts, paths, tickets and words, and must not leave it. This
// turns them into a lesson file the factory's own machine can learn from.
//
//   node learn-export.mjs export <lesson-file> <source> <project-dir> <events-dir> [<project-dir> <events-dir>]...
//       <events-dir> is learn-records.mjs events's output for that project.
//       Writes the lesson, prints it, and refuses (exit 3, nothing written) if
//       the closed-vocabulary check below fails.
//   node learn-export.mjs check <lesson-file>
//       the closed-vocabulary check alone (exit 3 on a foreign word)
//   node learn-export.mjs show <lesson-file>
//       the lesson as a person reads it before moving it
//   node learn-export.mjs ingest <inbox-dir> <out-dir>
//       checks every *.lesson.json in the inbox (a refused file is skipped, not
//       read), replays its cases through this machine's guard, and writes
//       <out-dir>/lessons.tsv, causes.tsv and fixtures.json (the cases this
//       guard still refuses, in tests/fixtures/guard-replay.json's format).
//
// How nothing leaks: an allowlist, not a scrubber. Every word in the lesson is
// built from a closed vocabulary (the factory's own words, shell and git
// words, generic technical words, {placeholders}); every other word becomes a
// placeholder, numbers of five digits or more become zeros of the same length,
// and free text (task briefs, messages, findings, ticket text, refusal
// reasons) is never exported, only counted. Then the file is read back and
// every word checked against that vocabulary, at export and again at ingest:
// a word outside it means the file is refused. A denylist (project and
// mission names, the user, the host, ~/.pi-factory/scrub-terms) is checked on
// top. Read the printed lesson before moving it anyway, and check that your
// employer allows taking it off the machine.
//
// What a case keeps: the shape of a refused call (commands, flags, operators,
// path structure), the guard rule that refused it, the context it ran in. A
// shape is useful only if the guard judges it as it judged the original:
// "faithful" says so, and ingest builds fixtures from faithful cases only.
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir, hostname, tmpdir, userInfo } from "node:os";
import { basename, dirname, join } from "node:path";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { check } from "./guard-rules.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const ls0 = (d) => { try { return readdirSync(d); } catch { return []; } };
const LESSON = 1;

// --- the closed vocabulary -------------------------------------------------------
const W = (s) => s.trim().split(/\s+/);
const PLACEHOLDERS = new Set(W(`root home tmp mission file pkg name arg var VAR flag body id agent model path str action`));
const VOCAB = new Set([
  // shell
  ...W(`sh bash zsh dash ksh fish cd pushd popd echo printf exit export unset set test true false for in do done if then
    else elif fi while until case esac function return local read source eval exec xargs env sudo time timeout seq sleep
    wait trap command type which shift break continue`),
  // tools
  ...W(`node npm npx pnpm yarn bun deno tsx python python3 pip pip3 git gh glab rm rmdir mv cp ln mkdir touch chmod chown
    cat head tail less grep egrep fgrep rg sed awk cut sort uniq wc tr tee find ls stat file diff patch tar gzip gunzip zip
    unzip curl wget jq yq date basename dirname realpath readlink pwd kill ps lsof make tap jest mocha vitest eslint
    prettier tsc standard c8 nyc docker mktemp ssh scp rsync open xdg`),
  // git
  ...W(`add am apply bisect blame branch checkout cherry pick clean clone commit config fetch format init log files merge
    base notes pull push rebase reflog remote reset restore revert rev parse show stash status switch tag worktree update
    ref index symbolic gc fsck describe shortlog object hash tree each name refs heads origin upstream`),
  // package managers, test runners
  ...W(`install ci run exec uninstall link pack publish list audit version bin modules node_modules lock`),
  // flags and generic technical words
  ...W(`no cov force hard soft all quiet verbose global save dev dry work oneline only porcelain staged cached short format
    pretty reporter recursive ignore max count depth single delete help watch bail inspect check fix ext cwd prefix silent
    json edit amend message author ff squash abbrev unified color filter exclude include output input path update prune
    tags theirs ours keep untracked continue abort skip onto since reverse follow numstat word null zero line lines number
    invert match extended regexp fixed strings before after context code write interactive parents target track mirror
    bare template workers jobs coverage spec terse require loader experimental pattern grep shallow unshallow pager diff3
    stat full raw replace new old text content mode async fresh fork workflow workflows task tasks options timeout id runid
    of on to at by is it as or and not with from into over up down out off one two first last next prev all any none
    error errors warn warning info debug trace fail failed failure pass passed ok done loop again ready step steps run runs
    tmp temp scratch verdict verdicts brief briefs journal light archive transcript sessions session agent agents subagent
    subagents lead judge worker workers review reviewer axis contract design spec plan ticket tickets mission missions
    decisions decision open question questions guard records notes usage report metrics retro retros learn draft drafts
    setup src lib test tests dist build scripts script factory pi local etc var usr dev bin opt private folders proc self
    hooks hook doc docs readme changelog license package index main mod app config configs fixture fixtures mock mocks
    unit integration e2e cache logs log out results result tsv md mjs cjs js ts tsx jsx json jsonl yml yaml sh txt html
    css py toml ini env cfg lockfile r1 r2 r3 r4 r5 pid now end issue type types util utils helper helpers common core
    api cli server client model models event events hook data schema schemas key keys value values state store home
    counts calls refusal lost round deviation message causes class bug cost retry weakness na gap intervention genuine
    environment flake other cases tool shape rule faithful seen steer resume stop cancel interrupt lesson source factory
    tmpdir ifs eof http https rc ret err dir dirs pass fail tmpfile logfile outfile`),
]);
// Words of the factory itself: guard rule ids, its scripts and agents.
const guardSrc = readFileSync(join(here, "guard-rules.mjs"), "utf8");
for (const m of guardSrc.matchAll(/\[\s*"([a-z][a-z-]*)",\s*\/|rule: "([a-z][a-z-]*)"|blocked\("([a-z][a-z-]*)"/g)) for (const w of (m[1] || m[2] || m[3]).split("-")) VOCAB.add(w);
const nameOf = (f) => f.replace(/\.(sh|mjs|cjs|html|txt|md)$/, "");
const COMPOUNDS = ["cherry-pick", "merge-base", "rev-parse", "ls-files", "cat-file", "for-each-ref", "symbolic-ref", "update-ref", "format-patch", "package-lock", "open-question", "no-cov", "dry-run", "git-dir", "work-tree", "name-only", "name-status", "no-pager", "set-upstream", "force-with-lease", "ff-only", "no-verify", "test-name-pattern"];
const factoryNames = [...readdirSync(here).map(nameOf), ...["agents/factory", "prompts"].flatMap((d) => ls0(join(here, "..", "..", ".pi", d)).map(nameOf))];
for (const n of [...factoryNames, ...COMPOUNDS]) { if (/^[a-z][a-z0-9-]*$/.test(n)) VOCAB.add(n); for (const w of n.split(/[-.]/)) if (/^[a-z]+$/.test(w)) VOCAB.add(w); }
const lower = (w) => w.toLowerCase();
const known = (w) => VOCAB.has(lower(w)) || PLACEHOLDERS.has(w) || /^[A-Za-z]$/.test(w);

// One word passes if each letter run is known and each digit run is short or
// zeros; a name of three parts or more (a-b-c) also needs the whole to be known
// (a branch or a ticket made of common words still says what the work is).
const RUN = /[A-Za-z]+|\d+/g;
function wordOk(w) {
  if (/^--?[A-Za-z]{1,3}$/.test(w)) return true;     // -rf, -ne, -C: too short to name anything
  for (const r of w.match(RUN) ?? []) {
    if (/^\d+$/.test(r)) { if (r.length > 4 && !/^0+$/.test(r)) return false; }
    else if (!known(r)) return false;
  }
  for (const part of w.split(/[^A-Za-z0-9_-]+/)) {
    if ((part.match(/[A-Za-z]+/g) ?? []).length >= 3 && !VOCAB.has(lower(part)) && !/^\{/.test(part)) return false;
  }
  return true;
}
const zeros = (s) => s.replace(/\d{5,}/g, (d) => "0".repeat(d.length));

// --- shapes ------------------------------------------------------------------------
// A variable keeps its name when the name is made of known words (log, out,
// FACTORY_ROLE, TMPDIR); any other is {VAR} where it is set and ${var} where it
// is read, which fill() turns back into one same variable.
const envOk = (n) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(n) && wordOk(n);
function shapeSegment(seg, prev, isLast) {
  if (/^\$\{?[A-Za-z_]\w*\}?$/.test(seg)) return envOk(seg.replace(/[${}]/g, "")) ? seg : "${var}";
  if (seg === "" || seg === "." || seg === ".." || seg === "~" || /^\*+$/.test(seg) || /^\{[A-Za-z]+\}$/.test(seg)) return seg;
  if (prev === ".scratch" && seg !== "light") return "{mission}";
  if (prev === "light" && isLast === false) return "{mission}";
  if (prev === "node_modules" && seg !== ".bin") return "{pkg}";
  const z = zeros(seg);
  if (wordOk(z)) return z;
  const ext = (seg.match(/\.([A-Za-z0-9]{1,5})$/) ?? [])[1];
  return isLast && ext && known(ext) ? `{file}.${ext}` : isLast ? "{file}" : "{name}";
}
export function shapePath(p) {
  const segs = String(p).split("/");
  return segs.map((s, i) => shapeSegment(s, segs[i - 1], i === segs.length - 1)).join("/");
}
function shapeWord(w) {
  if (/^\{[A-Za-z]+\}$/.test(w)) return w;
  let m;
  if ((m = w.match(/^([A-Za-z_][A-Za-z0-9_]*)=([\s\S]*)$/))) return `${envOk(m[1]) ? m[1] : "{VAR}"}=${m[2] ? shapeWord(m[2]) : ""}`;
  if ((m = w.match(/^(--?[A-Za-z][A-Za-z0-9-]{0,40})(?:=([\s\S]*))?$/))) {
    const flag = wordOk(m[1]) ? m[1] : "--{flag}";
    return m[2] === undefined ? flag : `${flag}=${m[2] ? shapeWord(m[2]) : ""}`;
  }
  if ((m = w.match(/^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/))) return envOk(m[1]) ? w : "${var}";
  if (/^\$[?!$@#0-9*-]$/.test(w)) return w;
  if ((m = w.match(/^'([\s\S]*)'$/)) && !m[1].includes("'")) return `'${shapeLine(m[1])}'`;
  if ((m = w.match(/^"([\s\S]*)"$/)) && !/(^|[^\\])"/.test(m[1])) return `"${shapeLine(m[1])}"`;
  if (/['"\\]/.test(w)) return shapeWord(w.replace(/\\(.)/g, "$1").replace(/["']/g, ""));
  if (/^\d+$/.test(w)) return zeros(w);
  if (/^[^A-Za-z0-9]{1,6}$/.test(w)) return w;
  if (w.includes("/") || /^[.~]/.test(w) || /\.[A-Za-z0-9]{1,5}$/.test(w)) return shapePath(w);
  const z = zeros(w);
  return wordOk(z) ? z : "{arg}";
}
// Shell tokens: operators kept, words shaped, quoted strings shaped inside.
const TOKEN = /(\s+)|(\d?>>?&\d|\d?>>?\|?|<<-?|&&|\|\||\$\(|[;&|()`<>{}])|((?:[^\s;&|()`<>'"\\{}$]|\$\{[A-Za-z_]\w*\}|\$(?!\()|\\[\s\S]|'[^']*'|"(?:\\[\s\S]|[^"\\])*"|\{[A-Za-z]+\})+)/y;
export function shapeLine(s) {
  let out = "", i = 0;
  while (i < s.length) {
    // A comment is free text: kept as a mark, never as words.
    if (s[i] === "#" && (i === 0 || /[\s;&|(]/.test(s[i - 1]))) {
      const nl = s.indexOf("\n", i);
      out += "# {str}"; i = nl < 0 ? s.length : nl; continue;
    }
    TOKEN.lastIndex = i;
    const m = TOKEN.exec(s);
    if (!m) { out += "{arg}"; break; }       // an unterminated quote: the rest is one word
    i = TOKEN.lastIndex;                      // before shapeWord: it shapes quoted strings with this same regex
    out += m[1] ? (m[1].includes("\n") ? "\n" : " ") : m[2] ? m[2] : shapeWord(m[3]);
  }
  return out;
}
// The guard's own reading of heredocs: data unless a shell runs it.
const SHELL_FED = /^(?:sudo\s+)?(?:\S*\/)?(?:ba|z|da|k|fi)?sh\b|^(?:eval|source|\.|xargs|exec|env\b.*\b(?:ba|z)?sh)\b/;
export function shapeCommand(cmd, { root = "", home = homedir() } = {}) {
  let s = String(cmd ?? "").replace(/^cd \S+ && /, "");
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  for (const [from, to] of [[root, "{root}"], [home, "{home}"], [tmpdir() === "/tmp" ? "" : tmpdir(), "{tmp}"]]) {
    if (from && from.length > 1) s = s.replace(new RegExp(`(?<![\\w.-])${esc(from)}(?=/|\\s|$|['"):;&|])`, "g"), to);
  }
  s = s.replace(/(?:\/Users|\/home)\/[^\s/'"]+/g, "{home}").replace(/\/(?:private\/)?var\/folders\/[^\s'"]*?\/T(?=\/|\s|$)/g, "{tmp}");
  s = s.replace(/<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1([^\n]*)\n[\s\S]*?\n\s*\2(?=\s*(\n|$|[;&|)]))/g, (all, _q, tag, rest, _e, at) => {
    const before = s.slice(0, at);
    const seg = before.slice(Math.max(before.lastIndexOf("\n"), before.lastIndexOf(";"), before.lastIndexOf("&"), before.lastIndexOf("|"), before.lastIndexOf("(")) + 1).trim();
    if (SHELL_FED.test(seg)) return all.replace(new RegExp(`\\b${tag}\\b`, "g"), "EOF");
    return `<<'EOF'${rest}\n{body}\nEOF`;
  });
  return shapeLine(s);
}
const ACTIONS = new Set(["status", "list", "get", "doctor", "interrupt", "steer", "resume", "run", "stop", "cancel"]);
export function shapeArgs(tool, args = {}, ctx = {}) {
  const a = args && typeof args === "object" ? args : {};
  if (tool === "bash") return { command: shapeCommand(a.command, ctx) };
  const out = {};
  for (const [k, v] of Object.entries(a)) {
    if (!wordOk(k)) continue;
    if (k === "workflow" || k === "path" || k === "file_path") out[k] = typeof v === "string" ? shapePath(v.split(ctx.root || "\0").join("{root}")) : "{path}";
    else if (k === "cwd") out[k] = v === ctx.root ? "{root}" : "{path}";
    else if (k === "agent") out[k] = typeof v === "string" && /^factory-[a-z-]+$/.test(v) && wordOk(v.replace(/-/g, " ")) ? v : "{agent}";
    else if (k === "action") out[k] = ACTIONS.has(v) ? v : "{action}";
    else if (k === "context") out[k] = v === "fresh" || v === "fork" ? v : "{arg}";
    else if (k === "options") out[k] = v && typeof v === "object" ? Object.fromEntries(Object.entries(v).filter(([x]) => wordOk(x)).map(([x, y]) => [x, y === "fresh" || y === "fork" || typeof y === "boolean" ? y : "{arg}"])) : "{arg}";
    else if (typeof v === "boolean") out[k] = v;
    else if (k === "id" || k === "runId") out[k] = "{id}";
    else if (k === "model") out[k] = "{model}";
    else if (typeof v === "string") out[k] = "{str}";       // task, message, content...: free text, never kept
    else if (typeof v === "number") out[k] = 0;
    else out[k] = "{arg}";
  }
  return out;
}

// --- the check, at export and at ingest ------------------------------------------------
const META = { lesson: /^1$/, source: /^[a-z][a-z0-9-]{0,15}$/, date: /^\d{4}-\d{2}-\d{2}$/, guard: /^[0-9a-f]{16}$/, factory: /^\d+\.\d+\.\d+(-[a-z]+\.\d+)?$/ };
export function foreignWords(lesson, deny = []) {
  const bad = new Set();
  if (!lesson || typeof lesson !== "object") return ["<not a lesson>"];
  for (const [k, re] of Object.entries(META)) if (!re.test(String(lesson[k] ?? ""))) bad.add(`${k}: ${String(lesson[k]).slice(0, 40)}`);
  const strings = [];
  const walk = (v, path) => {
    if (typeof v === "string") strings.push(v);
    else if (Array.isArray(v)) v.forEach((x) => walk(x, path));
    else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) { strings.push(k); walk(x, `${path}.${k}`); }
  };
  walk({ counts: lesson.counts, causes: lesson.causes, cases: lesson.cases }, "");
  for (const s of strings) {
    // A placeholder is {word} with a word of the list; what is left of a
    // token around placeholders is checked like any word.
    for (const w of s.split(/[\s;&|()`<>=,:"'$[\]]+/).filter(Boolean)) {
      const rest = w.replace(/\{([A-Za-z]+)\}/g, (all, x) => (PLACEHOLDERS.has(x) ? " " : "\u0000"));
      if (rest.includes("\u0000") || rest.split(" ").some((p) => p && !wordOk(p))) bad.add(w);
    }
  }
  const text = JSON.stringify(lesson).toLowerCase();
  for (const t of deny) if (t && t.length >= 3 && text.includes(t.toLowerCase())) bad.add(process.env.FACTORY_LESSON_DEBUG === "1" ? `denied term ${t}` : `denied term #${deny.indexOf(t) + 1}`);
  return [...bad];
}

// --- export ----------------------------------------------------------------------------
const REFUSED = /blocked by the factory guard/;
const CAUSE_CLASSES = new Set(["factory_bug", "factory_gap", "ticket_shape", "contract_shape", "model_weakness", "genuine_decision", "lead_deviation", "environment", "flake"]);
const sh = (cmd, args, cwd) => { try { return execFileSync(cmd, args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
const ls = (d) => (existsSync(d) ? readdirSync(d) : []);

// The contexts a call ran in, rebuilt empty: a project root and a worker's worktree.
function contexts() {
  const project = mkdtempSync(join(tmpdir(), "lesson-project-")); mkdirSync(join(project, ".git")); mkdirSync(join(project, ".factory"));
  const gitdir = mkdtempSync(join(tmpdir(), "lesson-gitdir-"));
  writeFileSync(join(gitdir, "HEAD"), "ref: refs/heads/pi-subagents/00-lesson-0-s0-t0\n");
  const worker = mkdtempSync(join(tmpdir(), "lesson-worker-")); writeFileSync(join(worker, ".git"), `gitdir: ${gitdir}\n`);
  return { project, worker, cwd: (context) => (context === "worker" ? worker : project) };
}
const contextOf = (who) => (who === "lead" ? "lead" : /^factory-worker/.test(who ?? "") ? "worker" : "judge");
// A shape made concrete again, to ask the guard about it.
const FILL = { mission: "m", file: "f", pkg: "lib", name: "x", arg: "a", var: "v", VAR: "V", flag: "flag", body: "x", id: "id1", agent: "factory-x", model: "p/m", path: "/opt/x", str: "x", action: "x" };
// root, home and tmp are this machine's; a fixture keeps them as {root},
// {home} and {tmp} (the replay test fills them on the machine that runs it).
export function fill(v, at = { root: "{root}", home: "{home}", tmp: "{tmp}" }) {
  const vals = { ...FILL, ...at };
  const f = (s) => s.replace(/\$\{var\}/g, "$V").replace(/\{([A-Za-z]+)\}/g, (all, k) => vals[k] ?? all);
  return typeof v === "string" ? f(v) : Array.isArray(v) ? v.map((x) => fill(x, at)) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fill(x, at)])) : v;
}
const here_ = (ctx) => ({ root: ctx.project, home: homedir(), tmp: tmpdir() });
const verdict = (tool, input, cwd) => check({ tool, input, cwd })?.rule ?? null;

function denyTerms(projects) {
  const terms = new Set();
  for (const p of projects) {
    const name = basename(p);
    terms.add(name);
    for (const part of name.split(/[-_.]/)) if (part.length >= 4 && !VOCAB.has(lower(part))) terms.add(part);
    const s = join(p, ".scratch");
    for (const m of [...ls(s), ...ls(join(s, "light")), ...ls(join(p, ".git", "pi-factory", "archive"))]) if (m.length >= 4 && m !== "light" && !wordOk(m)) terms.add(m);
    for (const m of [...ls(s), ...ls(join(s, "light"))]) if (m.length >= 6 && m.includes("-")) terms.add(m);
    const url = sh("git", ["remote", "get-url", "origin"], p);
    for (const part of url.split(/[/:@.]+/)) if (part.length >= 4 && !VOCAB.has(lower(part)) && !/^(https?|git|com|org|net|www)$/.test(part)) terms.add(part);
  }
  for (const t of [userInfo().username, hostname().split(".")[0], sh("git", ["config", "user.name"]), sh("git", ["config", "user.email"])]) if (t && t.length >= 3) terms.add(t);
  const scrub = join(homedir(), ".pi-factory", "scrub-terms");
  if (existsSync(scrub)) for (const t of readFileSync(scrub, "utf8").split("\n").map((x) => x.trim())) if (t && !t.startsWith("#")) terms.add(t);
  return [...terms].filter((t) => t.length >= 3 && !VOCAB.has(lower(t)) && !PLACEHOLDERS.has(t));
}

function taxonomyRows(project) {
  const f = join(project, ".git", "pi-factory", "learn", "taxonomy.tsv");
  if (!existsSync(f)) return [];
  const [head, ...rows] = readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => l.split("\t"));
  const col = (n) => head.indexOf(n);
  return rows.map((r) => ({
    class: CAUSE_CLASSES.has(r[col("cause_class")]) ? r[col("cause_class")] : "other",
    status: /^fixed/i.test(r[col("status")] ?? "") ? "fixed" : /^open/i.test(r[col("status")] ?? "") ? "open" : "na",
    cost: /round/i.test(r[col("cost")] ?? "") ? "round" : /retry|refus/i.test(r[col("cost")] ?? "") ? "retry" : /human|interven|decision|answer/i.test(r[col("cost")] ?? "") ? "intervention" : "other",
  }));
}

function exportLesson(file, source, pairs) {
  const ctx = contexts();
  const cases = new Map();
  const counts = { calls: 0, guard_refusal: 0, lost_round: 0, lead_deviation: 0, human_message: 0 };
  const causes = [];
  for (const [project, events] of pairs) {
    const root = sh("git", ["rev-parse", "--show-toplevel"], project) || project;
    const calls = JSON.parse(readFileSync(join(events, "calls.json"), "utf8"));
    counts.calls += calls.length;
    for (const row of readFileSync(join(events, "events.tsv"), "utf8").split("\n").slice(1).filter(Boolean)) {
      const k = row.split("\t")[0]; if (k in counts) counts[k]++;
    }
    causes.push(...taxonomyRows(project));
    for (const c of calls.filter((x) => REFUSED.test(x.result ?? ""))) {
      const context = contextOf(c.who);
      const shape = shapeArgs(c.tool, c.args, { root, home: homedir() });
      const key = JSON.stringify([context, c.tool, shape]);
      if (cases.has(key)) { cases.get(key).seen++; continue; }
      const original = { ...c.args };
      if (typeof original.command === "string") original.command = original.command.replace(/^cd \S+ && /, "").split(root).join(ctx.project);
      if (typeof original.cwd === "string") original.cwd = original.cwd === root ? ctx.project : original.cwd;
      const then = verdict(c.tool, original, ctx.cwd(context));
      const shaped = verdict(c.tool, fill(shape, here_(ctx)), ctx.cwd(context));
      cases.set(key, { context, tool: wordOk(c.tool) ? c.tool : "{arg}", shape, rule: then ?? "none", faithful: then === shaped, seen: 1 });
    }
  }
  const version = (() => {
    for (const f of [join(here, "..", "..", "package.json"), join(here, "..", "..", ".factory", "VERSION")]) {
      try { const t = readFileSync(f, "utf8"); return (f.endsWith(".json") ? JSON.parse(t).version : t).trim(); } catch { /* next */ }
    }
    return "0.0.0";
  })();
  const lesson = {
    lesson: LESSON, source, date: new Date().toISOString().slice(0, 10),
    guard: createHash("sha256").update(guardSrc).digest("hex").slice(0, 16),
    factory: META.factory.test(version) ? version : "0.0.0", counts, causes, cases: [...cases.values()],
  };
  const bad = foreignWords(lesson, denyTerms(pairs.map(([p]) => p)));
  if (bad.length) {
    console.error(`learn-export: refusing to write: ${bad.length} word(s) outside the vocabulary or on the denylist (not printed here; run the check on a copy to see them). Nothing was written.`);
    if (process.env.FACTORY_LESSON_DEBUG === "1") console.error(bad.join("\n"));
    process.exit(3);
  }
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(lesson, null, 1) + "\n");
  return lesson;
}

function show(lesson) {
  const L = [`lesson from "${lesson.source}", ${lesson.date}, factory ${lesson.factory}, guard ${lesson.guard}`];
  L.push(`counts: ${Object.entries(lesson.counts).map(([k, v]) => `${k} ${v}`).join(", ")}`);
  const by = {};
  for (const c of lesson.causes) by[c.class] = (by[c.class] ?? 0) + 1;
  L.push(`causes (taxonomy rows): ${Object.entries(by).map(([k, v]) => `${k} ${v}`).join(", ") || "none"}`);
  L.push(`refused calls (${lesson.cases.length} shapes; "~" = the shape is judged differently from the original, not used as a test):`);
  for (const c of lesson.cases) L.push(`  ${c.faithful ? " " : "~"} [${c.context} ${c.tool} ${c.rule} x${c.seen}] ${JSON.stringify(c.tool === "bash" ? c.shape.command : c.shape).slice(0, 300)}`);
  return L.join("\n");
}

// --- ingest ----------------------------------------------------------------------------
function ingest(inbox, out) {
  mkdirSync(out, { recursive: true });
  const ctx = contexts();
  const rows = [["source", "date", "guard", "context", "tool", "rule_then", "rule_now", "faithful", "seen", "shape"]];
  const causeRows = [["source", "date", "class", "status", "cost"]];
  const fixtures = [];
  let files = 0, refused = 0;
  for (const f of ls(inbox).filter((x) => x.endsWith(".lesson.json")).sort()) {
    let lesson; try { lesson = JSON.parse(readFileSync(join(inbox, f), "utf8")); } catch { lesson = null; }
    const bad = foreignWords(lesson);
    if (bad.length) { refused++; console.error(`ingest: ${f} refused: ${bad.length} word(s) outside the vocabulary; not read`); continue; }
    files++;
    for (const c of lesson.causes) causeRows.push([lesson.source, lesson.date, c.class, c.status, c.cost]);
    lesson.cases.forEach((c, i) => {
      const input = fill(c.shape, here_(ctx));
      const now = c.faithful ? verdict(c.tool, input, ctx.cwd(c.context)) ?? "none" : "unknown";
      rows.push([lesson.source, lesson.date, lesson.guard, c.context, c.tool, c.rule, now, c.faithful, c.seen, JSON.stringify(c.tool === "bash" ? c.shape.command : c.shape)]);
      if (c.faithful && now !== "none") fixtures.push({ id: `L-${lesson.source}-${lesson.date}-${String(i + 1).padStart(2, "0")}`, context: c.context === "judge" ? "judge" : c.context, tool: c.tool, rule: now, seen: c.seen, input: fill(c.shape) });
    });
  }
  const tsv = (r) => r.map((x) => x.map((y) => String(y).replace(/[\t\n]/g, " ")).join("\t")).join("\n") + "\n";
  writeFileSync(join(out, "lessons.tsv"), tsv(rows));
  writeFileSync(join(out, "causes.tsv"), tsv(causeRows));
  writeFileSync(join(out, "fixtures.json"), JSON.stringify(fixtures, null, 1) + "\n");
  const cases = rows.length - 1, passing = rows.slice(1).filter((r) => r[6] === "none").length;
  const byClass = {};
  for (const r of causeRows.slice(1)) byClass[r[2]] = (byClass[r[2]] ?? 0) + 1;
  console.log(`lessons: ${files} read${refused ? `, ${refused} refused` : ""}; ${cases} refused shapes: ${passing} now pass here, ${fixtures.length} still refused (candidates for guard-replay.json: a fix, or a true block), ${rows.slice(1).filter((r) => r[6] === "unknown").length} not faithful`);
  if (causeRows.length > 1) console.log(`causes from elsewhere: ${Object.entries(byClass).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", ")}`);
  return { files, refused, cases, passing, fixtures };
}

// --- main ------------------------------------------------------------------------------
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === "export") {
    const [file, source, ...pp] = rest;
    if (!file || !META.source.test(source ?? "") || !pp.length || pp.length % 2) { console.error("usage: learn-export.mjs export <lesson-file> <source: a-z0-9-, 16 max> <project-dir> <events-dir>..."); process.exit(2); }
    const pairs = []; for (let i = 0; i < pp.length; i += 2) pairs.push([pp[i], pp[i + 1]]);
    console.log(show(exportLesson(file, source, pairs)));
    console.log(`\nwritten: ${file}\nRead it above before moving it. Only the factory's vocabulary is in it; your employer's rules on taking files off this machine still apply.`);
  } else if (cmd === "check") {
    let lesson; try { lesson = JSON.parse(readFileSync(rest[0], "utf8")); } catch { lesson = null; }
    const bad = foreignWords(lesson);
    if (bad.length) { console.error(`refused: ${bad.join(", ")}`); process.exit(3); }
    console.log("ok: every word is in the factory's vocabulary");
  } else if (cmd === "show") {
    console.log(show(JSON.parse(readFileSync(rest[0], "utf8"))));
  } else if (cmd === "ingest") {
    if (rest.length < 2) { console.error("usage: learn-export.mjs ingest <inbox-dir> <out-dir>"); process.exit(2); }
    ingest(rest[0], rest[1]);
  } else {
    console.error("usage: learn-export.mjs export|check|show|ingest (see the header)"); process.exit(2);
  }
}
