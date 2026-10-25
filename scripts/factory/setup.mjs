#!/usr/bin/env node
// factory setup (D102, proposal P18): the project's factory setup, found and
// proven instead of typed and guessed. Run from the project folder (a monorepo
// project: its own folder); one project at a time, never the machine.
//
//   1. Discover: the project's manifests, CI file and install scripts say what
//      runs its tests and lint (setup-discover.mjs).
//   2. Rehearse: each command runs as a worker would run it: in a fresh
//      worktree of your working tree, dependencies linked by the worktree hook
//      (D65), credential variables unset (D100), package managers offline and
//      proxies pointed at a closed port. The test command runs twice (green
//      both times), then with a planted failing test file (it must turn red,
//      because of that file); FACTORY_TEST_FILES_CMD runs on that file alone.
//   3. Check this machine as the project's missions will use it (env-check.mjs).
//   4. Report: .factory/setup.md, the decisions it needs from you first. With
//      --write, the commands that passed go into an empty FACTORY_* line of
//      .factory/commands.env; a value you set is never replaced.
//
// Usage: factory setup [--write] [--no-rehearse] [--timeout <seconds per run>]
// Exit: 0 when the test command passed its rehearsal and nothing is blocking;
//       1 otherwise (setup.md says why).
//
// Offline is as far as proxies and package managers go (npm, yarn, pnpm, pip,
// uv, cargo, go): a program opening its own socket is not stopped. It is a
// rehearsal of the worker's conditions, not a sandbox.
import { spawnSync, execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync, copyFileSync, lstatSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { secretEnvNames } from "./guard-rules.mjs";
import { redact } from "./redact.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const write = args.includes("--write");
const rehearse = !args.includes("--no-rehearse");
const timeoutS = Number(args[args.indexOf("--timeout") + 1]) > 0 && args.includes("--timeout") ? Number(args[args.indexOf("--timeout") + 1]) : 600;
const KINDS = { test: "FACTORY_TEST_CMD", testFiles: "FACTORY_TEST_FILES_CMD", lint: "FACTORY_LINT_CMD", extra: "FACTORY_EXTRA_CMD" };

const sh = (cmd, a, o = {}) => { try { return execFileSync(cmd, a, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], ...o }).trim(); } catch { return ""; } };
const project = process.cwd();
if (!sh("git", ["rev-parse", "--is-inside-work-tree"])) { console.error("factory setup: not in a git repository"); process.exit(2); }
const gitRoot = sh("git", ["rev-parse", "--show-toplevel"]);
const prefix = sh("git", ["rev-parse", "--show-prefix"]).replace(/\/$/, "");
const commonDir = sh("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"]) || join(gitRoot, ".git");

// ------------------------------------------------------------------ 1. discover
const disc = JSON.parse(spawnSync(process.execPath, [join(here, "setup-discover.mjs"), project], { encoding: "utf8" }).stdout || "{}");
// What commands.env says today, exactly as the factory's scripts read it (sourced by bash).
const current = (() => {
  if (!existsSync(".factory/commands.env")) return {};
  const r = spawnSync("bash", ["-c", `. .factory/commands.env >/dev/null 2>&1; printf '%s\\0' ${Object.values(KINDS).map((k) => `"\${${k}:-}"`).join(" ")}`], { encoding: "utf8" });
  const v = (r.stdout || "").split("\0");
  return Object.fromEntries(Object.keys(KINDS).map((k, i) => [k, v[i] || ""]));
})();
const chosen = {};
for (const k of Object.keys(KINDS)) {
  if (current[k]) chosen[k] = { cmd: current[k], source: ".factory/commands.env (yours)", mine: true };
  else if (disc.candidates?.[k]?.[0]) chosen[k] = { ...disc.candidates[k][0], mine: false };
}

// ------------------------------------------------------------------ 2. rehearse
const results = {};           // kind → { status: pass|fail|warn|skip, checks: [{ ok, text }], tail }
const logDir = join(commonDir, "pi-factory", "setup", new Date().toISOString().replace(/[:.]/g, "-"));
let snapshot = "";
const workerEnv = () => {
  let modelsJson = null;
  try { modelsJson = JSON.parse(readFileSync(join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"), "models.json"), "utf8")); } catch {}
  const env = { ...process.env };
  for (const n of secretEnvNames({ env, modelsJson })) delete env[n];
  const dead = "http://127.0.0.1:9";
  Object.assign(env, {
    HTTP_PROXY: dead, HTTPS_PROXY: dead, http_proxy: dead, https_proxy: dead, ALL_PROXY: dead, all_proxy: dead, NO_PROXY: "", no_proxy: "",
    npm_config_offline: "true", npm_config_audit: "false", npm_config_fund: "false", npm_config_update_notifier: "false",
    npm_config_cache: join(tmp, "npm-cache"), YARN_ENABLE_OFFLINE_MODE: "1", PIP_NO_INDEX: "1", PIP_DISABLE_PIP_VERSION_CHECK: "1",
    UV_OFFLINE: "1", GOPROXY: "off", CARGO_NET_OFFLINE: "true",
  });
  return env;
};
const NETWORK = /Need to install the following packages|ENOTCACHED|ECONNREFUSED 127\.0\.0\.1:9|ENOTFOUND|EAI_AGAIN|Could not resolve host|Temporary failure in name resolution|getaddrinfo|No matching distribution found|failed to download|module lookup disabled by GOPROXY=off|attempting to make an HTTP request, but --offline was specified/i;
const NOT_STARTED = /command not found|: not found|No module named|No such file or directory|Cannot find module|ENOENT|is not recognized as/i;
let tmp = "";

function run(label, cmd, cwd, env) {
  const t0 = Date.now();
  const r = spawnSync("bash", ["-c", cmd], { cwd, env, encoding: "utf8", timeout: timeoutS * 1000, maxBuffer: 64 * 1024 * 1024 });
  const text = (r.stdout || "") + (r.stderr || "");
  try { mkdirSync(logDir, { recursive: true }); writeFileSync(join(logDir, `${label}.log`), redact(`$ ${cmd}\n${text}`)); } catch {}
  const code = r.error?.code === "ETIMEDOUT" ? "timeout" : r.status ?? (r.signal ? `signal ${r.signal}` : 1);
  return { code, text, secs: ((Date.now() - t0) / 1000).toFixed(1), tail: redact(text.trimEnd().split("\n").slice(-12).join("\n")) };
}

if (rehearse && chosen.test) {
  tmp = mkdtempSync(join(tmpdir(), "factory-setup-"));
  const wt = join(tmp, "wt");
  // Your working tree as it is: tracked changes (git stash create) plus new,
  // non-ignored files. What you haven't committed is rehearsed, and named.
  snapshot = sh("git", ["stash", "create"]) || "HEAD";
  const untracked = sh("git", ["-C", gitRoot, "ls-files", "--others", "--exclude-standard"]).split("\n").filter(Boolean);
  const changed = sh("git", ["-C", gitRoot, "status", "--porcelain", "--untracked-files=no"]).split("\n").filter(Boolean);
  results.snapshot = { changed: changed.length, added: untracked.length, ref: snapshot === "HEAD" ? sh("git", ["rev-parse", "--short", "HEAD"]) : "working tree" };
  const cleanup = () => { try { execFileSync("git", ["-C", gitRoot, "worktree", "remove", "--force", wt], { stdio: "ignore" }); } catch {} try { rmSync(tmp, { recursive: true, force: true }); } catch {} };
  process.on("exit", cleanup);
  for (const s of ["SIGINT", "SIGTERM"]) process.on(s, () => process.exit(130));
  execFileSync("git", ["-C", gitRoot, "worktree", "add", "-q", "--detach", wt, snapshot], { stdio: "ignore" });
  for (const f of untracked) {
    const from = join(gitRoot, f), to = join(wt, f);
    try { if (lstatSync(from).isFile()) { mkdirSync(dirname(to), { recursive: true }); copyFileSync(from, to); } } catch {}
  }
  // Dependencies and factory links, exactly as a worker gets them (D65, D92).
  const hook = spawnSync(process.execPath, [join(here, "worktree-hook.mjs")], {
    input: JSON.stringify({ repoRoot: gitRoot, worktreePath: wt, agentCwd: join(wt, prefix), index: 0 }),
    env: { ...process.env, FACTORY_PROJECT_PREFIX: prefix }, encoding: "utf8",
  });
  let synthetic = [];
  try { synthetic = JSON.parse(hook.stdout).syntheticPaths || []; } catch {}
  const cwd = join(wt, prefix);
  const env = workerEnv();
  const leftovers = () => sh("git", ["-C", wt, "status", "--porcelain", "--untracked-files=all"]).split("\n").filter(Boolean)
    .map((l) => l.slice(3)).filter((p) => !synthetic.some((s) => p === s || p.startsWith(s + "/")) && !untracked.includes(p));
  const probeHit = (t) => /factory[- ]setup[- ]probe/i.test(t);

  // The test command: twice on the base, then with a failing file.
  {
    const c = chosen.test.cmd, checks = [];
    const npx = c.match(/^\s*npx\s+(?:--?\S+\s+)*([@\w./-]+)/);
    if (npx && !existsSync(join(cwd, "node_modules/.bin", npx[1].split("/").pop())) && !existsSync(join(wt, "node_modules/.bin", npx[1].split("/").pop())))
      checks.push({ ok: false, text: `\`npx ${npx[1]}\` isn't installed in the project: npx would download it, and a worker is offline` });
    const a = run("test-1", c, cwd, env), b = run("test-2", c, cwd, env);
    const green = a.code === 0 && b.code === 0;
    if (NETWORK.test(a.text + b.text)) checks.push({ ok: false, text: "it reached for the network (a download or a lookup); a worker is offline" });
    const notStarted = a.code !== 0 && (a.code === 127 || NOT_STARTED.test(a.text));
    if (notStarted) checks.push({ ok: false, text: `it didn't start (exit ${a.code}): ${(a.text.match(new RegExp(`.*(${NOT_STARTED.source}).*`, "i")) || [""])[0].trim().slice(0, 160)}` });
    else checks.push(green ? { ok: true, text: `green twice offline, credentials unset (${a.secs}s, ${b.secs}s)` }
      : a.code !== b.code ? { ok: false, text: `flaky: exit ${a.code}, then ${b.code}` }
      : { ok: false, text: `red on your code: exit ${a.code}; the base must be green before a mission` });
    const left = leftovers();
    if (left.length) checks.push({ ok: "warn", text: `it leaves files in the tree: ${left.slice(0, 5).join(", ")}${left.length > 5 ? "…" : ""} (a worker's patch would carry them: add them to .gitignore)` });
    let tail = green ? "" : (b.code !== 0 ? b : a).tail;
    if (green && disc.probe) {
      const pf = join(cwd, disc.probe.file);
      mkdirSync(dirname(pf), { recursive: true }); writeFileSync(pf, disc.probe.content);
      const p = run("test-probe", c, cwd, env);
      if (p.code === 0) checks.push({ ok: false, text: `a failing test file (${disc.probe.file}) leaves it green: it doesn't run that kind of file, or not from there` });
      else if (probeHit(p.text)) checks.push({ ok: true, text: `a failing test file (${disc.probe.file}) turns it red, because of that file` });
      else { checks.push({ ok: "warn", text: `with a failing test file it goes red, but its output doesn't name the file: check that the runner loads ${disc.probe.file}` }); tail = p.tail; }
      if (chosen.testFiles) {
        const fc = chosen.testFiles.cmd.split("{files}").join(disc.probe.file);
        const f = run("test-files-probe", fc, cwd, env);
        const fr = { status: "pass", checks: [] };
        if (!chosen.testFiles.cmd.includes("{files}")) fr.checks.push({ ok: false, text: "it has no {files} placeholder" });
        else if (f.code === 0) fr.checks.push({ ok: false, text: `on the failing file alone it is green: it doesn't run the files it's given` });
        else if (NOT_STARTED.test(f.text) && !probeHit(f.text)) fr.checks.push({ ok: false, text: `it didn't start (exit ${f.code})` });
        else if (probeHit(f.text)) fr.checks.push({ ok: true, text: "on the failing file alone it is red, because of that file" });
        else fr.checks.push({ ok: "warn", text: "on the failing file alone it is red, but its output doesn't name the file" });
        fr.status = fr.checks.some((x) => x.ok === false) ? "fail" : fr.checks.some((x) => x.ok === "warn") ? "warn" : "pass";
        fr.tail = fr.status === "pass" ? "" : f.tail;
        results.testFiles = fr;
      }
      rmSync(pf, { force: true });
    } else if (green) checks.push({ ok: "warn", text: "no failing-file check for this ecosystem: setup can't prove a broken test turns it red" });
    if (!green && chosen.testFiles) results.testFiles = { status: "skip", checks: [{ ok: "warn", text: "not rehearsed: the test command isn't green yet" }] };
    results.test = { status: checks.some((x) => x.ok === false) ? "fail" : checks.some((x) => x.ok === "warn") ? "warn" : "pass", checks, tail };
  }
  // Lint: runs to the end (its errors are baselined, D62); the extra check: green.
  for (const k of ["lint", "extra"]) {
    if (!chosen[k]) continue;
    const r = run(k, chosen[k].cmd, cwd, env), checks = [];
    if (NETWORK.test(r.text)) checks.push({ ok: false, text: "it reached for the network" });
    if (r.code === 127 || r.code === "timeout" || (r.code !== 0 && NOT_STARTED.test(r.text) && !/error/i.test(r.text.replace(NOT_STARTED, ""))))
      checks.push({ ok: false, text: `it didn't run (exit ${r.code})` });
    else if (k === "lint") {
      const errors = r.text.split("\n").filter((l) => /(^|[^A-Za-z])error([^A-Za-z]|$)/i.test(l)).length;
      checks.push({ ok: true, text: `ran offline (${r.secs}s): ${errors} error line(s) today, the baseline (factory health baseline)` });
    } else checks.push(r.code === 0 ? { ok: true, text: `green offline (${r.secs}s)` } : { ok: false, text: `red on your code (exit ${r.code}): an extra check must be green before a mission` });
    results[k] = { status: checks.some((x) => x.ok === false) ? "fail" : "pass", checks, tail: checks.some((x) => x.ok === false) ? r.tail : "" };
  }
}

// ------------------------------------------------------------------ 3. this machine
const envCheck = (() => {
  const r = spawnSync(process.execPath, [join(here, "env-check.mjs"), "--strict", "--json"], { encoding: "utf8", env: process.env });
  try { return JSON.parse(r.stdout); } catch { return []; }
})();

// ------------------------------------------------------------------ 4. report
const icon = (s) => ({ pass: "✓", fail: "✗", warn: "!", skip: "–" }[s] || "–");
const decide = (disc.findings || []).filter((f) => f.level === "decide");
const warns = (disc.findings || []).filter((f) => f.level === "warn");
const infos = (disc.findings || []).filter((f) => f.level === "info");
const machineBad = envCheck.filter((f) => f.level === "bad");
const testOk = !rehearse ? Boolean(chosen.test) : results.test?.status === "pass" || results.test?.status === "warn";
const L = [];
L.push(`# Factory setup`, "", `Generated by \`factory setup\` (D102) on ${new Date().toISOString().slice(0, 10)}${prefix ? `, project \`${prefix}\`` : ""}. Ecosystems: ${(disc.ecosystems || []).join(", ") || "none found"}.`);
if (results.snapshot) L.push("", `Rehearsed on ${results.snapshot.ref === "working tree" ? `your working tree (${results.snapshot.changed} changed and ${results.snapshot.added} new file(s) not committed yet: a worker gets only what is committed)` : `commit ${results.snapshot.ref}`}, offline, credential variables unset, dependencies linked as a worker gets them.`);
L.push("", "## Commands", "");
for (const [k, envName] of Object.entries(KINDS)) {
  const c = chosen[k];
  if (!c) { L.push(`- **${envName}**: none found${k === "test" ? " (required: the factory refuses to build without one, D44)" : ""}`); continue; }
  const r = results[k];
  L.push(`- ${r ? icon(r.status) : "–"} **${envName}** \`${c.cmd}\` (from ${c.source})`);
  for (const ch of r?.checks || []) L.push(`  - ${ch.ok === true ? "✓" : ch.ok === "warn" ? "!" : "✗"} ${ch.text}`);
  if (r?.tail) L.push("", "    ```", ...r.tail.split("\n").map((x) => `    ${x}`), "    ```", "");
  const others = (disc.candidates?.[k] || []).filter((x) => x.cmd !== c.cmd);
  if (others.length) L.push(`  - other candidates: ${others.map((x) => `\`${x.cmd}\` (${x.source})`).join("; ")}`);
}
if ((disc.ci || []).length) { L.push("", "What the team's CI runs:", ""); for (const c of disc.ci) L.push(`- ${c.kind}: \`${c.cmd}\` (${c.source})`); }
if (decide.length) { L.push("", "## Decisions for you", ""); decide.forEach((f, i) => L.push(`${i + 1}. **${f.topic}**: ${f.text}`)); }
if (warns.length || infos.length) { L.push("", "## Findings", ""); for (const f of [...warns, ...infos]) L.push(`- ${f.level === "warn" ? "!" : "·"} **${f.topic}**: ${f.text}`); }
L.push("", "## This machine", "", "How this project's missions will run here (not part of the project; `factory doctor` checks the same):", "");
for (const f of envCheck) L.push(`- ${{ ok: "✓", warn: "!", bad: "✗" }[f.level]} ${f.text}`);
writeFileSync(".factory/setup.md", redact(L.join("\n")) + "\n");

// --write: the commands that passed, into empty lines only.
const written = [];
if (write && !rehearse) console.log("factory setup: --write needs the rehearsal (only commands that passed it are written)");
if (write && rehearse && existsSync(".factory/commands.env")) {
  let text = readFileSync(".factory/commands.env", "utf8");
  for (const [k, envName] of Object.entries(KINDS)) {
    const c = chosen[k], r = results[k];
    if (!c || c.mine || !rehearse || (r?.status !== "pass" && r?.status !== "warn")) continue;
    const line = `${envName}=${JSON.stringify(c.cmd).replace(/\$/g, "\\$").replace(/`/g, "\\`")}`;
    const re = new RegExp(`^${envName}=(""|'')?\\s*$`, "m");
    if (re.test(text)) text = text.replace(re, line); else text += `\n${line}\n`;
    written.push(envName);
  }
  writeFileSync(".factory/commands.env", text);
}

// Summary on the terminal: what passed, what you decide, what to run next.
console.log("Setup (D102)");
for (const [k, envName] of Object.entries(KINDS)) {
  const c = chosen[k], r = results[k];
  if (!c) { if (k === "test") console.log(`  ✗ ${envName}: none found`); continue; }
  const why = r ? (r.checks.find((x) => x.ok === false) || r.checks.find((x) => x.ok === "warn") || r.checks[r.checks.length - 1])?.text : rehearse ? "" : "not rehearsed (--no-rehearse)";
  console.log(`  ${r ? icon(r.status) : "–"} ${envName}  ${c.cmd}${why ? `\n      ${why}` : ""}`);
}
if (decide.length) { console.log(`\n  ${decide.length} decision(s) for you, in .factory/setup.md:`); decide.forEach((f, i) => console.log(`  ${i + 1}. ${f.topic}: ${f.text.length > 160 ? f.text.slice(0, 157) + "…" : f.text}`)); }
const notable = [...warns.map((f) => ({ ...f, mark: "!" })), ...envCheck.filter((f) => f.level !== "ok").map((f) => ({ topic: "this machine", text: f.text, mark: f.level === "bad" ? "✗" : "!" }))];
if (notable.length) { console.log(`\n  ${notable.length} finding(s):`); for (const f of notable) console.log(`  ${f.mark} ${f.topic}: ${f.text.length > 160 ? f.text.slice(0, 157) + "…" : f.text}`); }
console.log(`\n  report: .factory/setup.md${rehearse ? `   logs: ${logDir}` : ""}`);
if (written.length) console.log(`  written to .factory/commands.env: ${written.join(", ")}${written.includes("FACTORY_LINT_CMD") ? "  → then: factory health baseline" : ""}`);
else if (!write && Object.entries(KINDS).some(([k]) => chosen[k] && !chosen[k].mine && results[k] && results[k].status !== "fail")) console.log("  next: factory setup --write puts the commands that passed into .factory/commands.env");
process.exit(testOk && !machineBad.length ? 0 : 1);
