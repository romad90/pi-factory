#!/usr/bin/env node
// B8: the prompts (slash commands) the factory's docs name, checked against
// .pi/prompts, and against the pi process this runs under. In deps-node-22
// the CHEATSHEET named /factory-deps and pi had no such command: the session
// was started before the prompt was added, and pi reads prompts at start.
//
// Usage: node prompts-check.mjs <package-root> <prompts-dir>
// Prints one line per finding, nothing when all is well:
//   missing\t/<name>\t<file naming it>     (exit 1)
//   stale\t<newest prompt file>\t<its time>\t<pi's start time>
// PROMPTS_CHECK_PI_STARTED_MS sets pi's start time (tests); else it is read with ps
// from the nearest ancestor process that is pi, and unknown without one.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";

// Where people read the commands: not the ADR or proposals, which keep history.
const DOCS = ["CHEATSHEET.md", "README.md", "docs", "docs/agents"];
const NAMED = /`\/(factory(?:-[a-z]+)*)[ `]/g;

const mdFiles = (dir) => {
  try { return readdirSync(dir).filter((f) => f.endsWith(".md")).map((f) => join(dir, f)); } catch { return []; }
};

// name → first file (relative to the package) that names it
export function namedPrompts(pkg, promptsDir) {
  const files = [];
  for (const d of DOCS) {
    const p = join(pkg, d);
    if (d.endsWith(".md")) { if (existsSync(p)) files.push(p); } else files.push(...mdFiles(p));
  }
  files.push(...mdFiles(promptsDir));
  const names = new Map();
  for (const f of files) {
    for (const m of readFileSync(f, "utf8").matchAll(NAMED)) {
      if (!names.has(m[1])) names.set(m[1], f.startsWith(pkg + "/") ? f.slice(pkg.length + 1) : f);
    }
  }
  return names;
}

export function missingPrompts(pkg, promptsDir) {
  return [...namedPrompts(pkg, promptsDir)]
    .filter(([name]) => !existsSync(join(promptsDir, `${name}.md`)))
    .map(([name, file]) => ({ name, file }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function newestPrompt(promptsDir) {
  let best = null;
  for (const f of mdFiles(promptsDir)) {
    const t = statSync(f).mtimeMs;
    if (!best || t > best.mtimeMs) best = { name: basename(f), mtimeMs: t };
  }
  return best;
}

// ps -o etime: [[dd-]hh:]mm:ss, on Linux and macOS alike.
export function parseEtime(s) {
  const m = String(s).trim().match(/^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/);
  if (!m) return null;
  const [, d = 0, h = 0, min, sec] = m;
  return ((Number(d) * 24 + Number(h)) * 60 + Number(min)) * 60 + Number(sec);
}

// pi itself, or node running pi's bin.
export function isPi(args) {
  const [a, b] = String(args).trim().split(/\s+/);
  if (basename(a || "") === "pi") return true;
  return /^node(js)?$/.test(basename(a || "")) && basename(b || "") === "pi";
}

function piStartedMs() {
  const env = process.env.PROMPTS_CHECK_PI_STARTED_MS;
  if (env !== undefined) return env === "" ? null : Number(env);
  let pid = process.ppid;
  for (let i = 0; i < 20 && pid > 1; i++) {
    let line;
    try { line = execFileSync("ps", ["-o", "ppid=,etime=,args=", "-p", String(pid)], { encoding: "utf8" }).trim(); } catch { return null; }
    const m = line.match(/^(\d+)\s+(\S+)\s+(.*)$/);
    if (!m) return null;
    if (isPi(m[3])) { const s = parseEtime(m[2]); return s === null ? null : Date.now() - s * 1000; }
    pid = Number(m[1]);
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [pkg, promptsDir] = process.argv.slice(2);
  if (!pkg || !promptsDir) { console.error("usage: prompts-check.mjs <package-root> <prompts-dir>"); process.exit(2); }
  const missing = missingPrompts(pkg, promptsDir);
  for (const { name, file } of missing) console.log(`missing\t/${name}\t${file}`);
  const started = piStartedMs();
  const newest = newestPrompt(promptsDir);
  // ps gives whole seconds: a second's slack.
  if (started !== null && newest && newest.mtimeMs > started + 1000) {
    console.log(`stale\t${newest.name}\t${new Date(newest.mtimeMs).toISOString()}\t${new Date(started).toISOString()}`);
  }
  process.exit(missing.length ? 1 : 0);
}
