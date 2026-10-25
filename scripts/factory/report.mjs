#!/usr/bin/env node
// factory report (D102): everything a diagnosis needs, as one redacted text,
// so a person helping you reads one block instead of screens of output.
// Run from the project folder.
//
// Usage: factory report [--full]
//   default   what is wrong or worth a look, and the facts needed to read it
//             (about 40 lines: short enough to photograph or paste)
//   --full    everything: every agent's model and route, commands.env, git status
// Prints the report and keeps a copy in <git-common-dir>/pi-factory/report.txt
// (never committed). Secrets go through redact.mjs; keys are never read.
import { spawnSync, execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { redact } from "./redact.mjs";
import { effectiveAgents, PACKAGE_ROOT } from "./effective-models.mjs";
import { gatewayOf } from "./models-probe.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const full = process.argv.includes("--full");
const sh = (cmd, a, o = {}) => { try { return execFileSync(cmd, a, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 60000, ...o }).trim(); } catch (e) { return (e.stdout || "").toString().trim(); } };
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return ""; } };
const L = [];
const line = (s = "") => L.push(s);

const branch = sh("git", ["branch", "--show-current"]);
const prefix = sh("git", ["rev-parse", "--show-prefix"]).replace(/\/$/, "");
const status = sh("git", ["status", "--porcelain"]).split("\n").filter(Boolean);
line(`factory report ${new Date().toISOString().replace(/\.\d+Z$/, "Z")}${full ? " (full)" : ""}`);
line(`project: ${prefix || "(repository root)"} · branch ${branch || "(detached)"} · ${status.length ? `${status.length} uncommitted` : "clean"}`);
const inst = read(join(PACKAGE_ROOT, ".factory/VERSION")).trim(), expect = read(".factory/VERSION").trim();
const head = sh("git", ["-C", PACKAGE_ROOT, "rev-parse", "--short=12", "HEAD"]), recorded = read(".factory/package-sha").trim().slice(0, 12);
line(`factory: ${inst || "?"} installed${expect ? `, project expects ${expect}` : ""}${head ? ` · commit ${head}${recorded && recorded !== head ? ` (CI runs ${recorded})` : ""}` : ""}${existsSync(".factory/package-dir") ? ` · folder ${read(".factory/package-dir").trim()}/ of its repository` : ""}`);
const pi = sh("pi", ["--version"]).split("\n")[0];
const subagents = (sh("pi", ["list"]).match(/pi-subagents@?[\d.]*/) || [""])[0];
line(`node ${process.version} · pi ${pi || "not found"}${subagents ? ` · ${subagents}` : ""}`);

// Pre-flight (D46): the lines that fail or warn, all of them with --full.
line(); line("Pre-flight");
const pre = spawnSync("bash", [join(here, "doctor.sh"), "--quick"], { encoding: "utf8", timeout: 120000 });
const preLines = ((pre.stdout || "") + (pre.stderr || "")).split("\n").filter((l) => l.trim() && l.trim() !== "Pre-flight");
for (const l of preLines) if (full || !/^\s*✓/.test(l)) line(l.replace(/^\s*/, "  "));

// Models: every agent with --full; else only the ones with something to say.
line(); line("Models");
const FLOATING = /(^|[\/:._-])(latest|current|default|stable|preview)$/i;
const agents = effectiveAgents();
const unsetNames = agents.filter((a) => !a.model || /[<>]/.test(a.model)).map((a) => a.name.replace(/^factory-/, ""));
if (!full && unsetNames.length > 2) line(`  ✗ no model for ${unsetNames.join(", ")}`);
for (const a of agents) {
  const unset = !a.model || /[<>]/.test(a.model);
  if (!full && unset && unsetNames.length > 2) continue;
  let host = ""; if (!unset) { const g = gatewayOf(a.model); try { host = g.base ? new URL(g.base).host : g.skip ? "(not probed)" : ""; } catch { host = g.base || ""; } }
  const note = unset ? "  ✗ no model" : FLOATING.test(a.model) ? "  ! floating alias" : "";
  if (full || note) line(`  ${a.name.replace(/^factory-/, "")}: ${unset ? "-" : a.model}${a.thinking ? ` @${a.thinking}` : ""}${host ? ` → ${host}` : ""}${note}`);
}
if (!full && !L[L.length - 1].startsWith("  ")) line("  every agent has a pinned model (--full lists them)");

// Commands: what is set (values with --full), and setup's last verdicts.
line(); line("Commands");
for (const k of ["FACTORY_TEST_CMD", "FACTORY_TEST_FILES_CMD", "FACTORY_LINT_CMD", "FACTORY_EXTRA_CMD"]) {
  const m = read(".factory/commands.env").match(new RegExp(`^${k}=(.*)$`, "m"));
  const v = m ? m[1].trim().replace(/^(["'])(.*)\1$/, "$2") : "";
  if (full || !v || k === "FACTORY_TEST_CMD") line(`  ${k}: ${v || "(empty)"}`);
}
const setup = read(".factory/setup.md");
if (setup) {
  const date = (setup.match(/on (\d{4}-\d{2}-\d{2})/) || [])[1] || "?";
  const verdicts = setup.split("\n").filter((l) => /^- [✓✗!–] \*\*FACTORY_/.test(l)).map((l) => l.replace(/^- /, "").replace(/\*\*/g, "").replace(/ \(from .*\)$/, ""));
  const decisions = (setup.match(/^## Decisions for you\n\n([\s\S]*?)(\n## |$)/m) || [, ""])[1].split("\n").filter((l) => /^\d+\./.test(l));
  line(`  setup ${date}: ${verdicts.map((v) => v.split(" ").slice(0, 2).join(" ")).join(", ") || "no rehearsal"}${decisions.length ? ` · ${decisions.length} decision(s) open` : ""}`);
  for (const d of decisions) line(`    ${d.replace(/\*\*/g, "").slice(0, 150)}`);
} else line("  no setup report yet: factory setup");

// Missions: where each one stands (next.sh), at most 8.
const missions = (() => { try { return readdirSync(".scratch", { withFileTypes: true }).filter((d) => d.isDirectory() && existsSync(join(".scratch", d.name, "spec.md"))).map((d) => d.name); } catch { return []; } })();
if (missions.length) {
  line(); line("Missions");
  for (const m of missions.slice(0, 8)) {
    const out = sh("bash", [join(here, "next.sh"), m]);
    const step = (out.match(/^STEP: (.*)$/m) || [, "?"])[1], next = (out.match(/^NEXT → (.*)$/m) || [, ""])[1];
    line(`  ${m}: ${step}${next ? ` → ${next.slice(0, 110)}` : ""}`);
  }
}

if (full && status.length) { line(); line("git status"); for (const s of status.slice(0, 20)) line(`  ${s}`); }

const text = redact(L.join("\n")) + "\n";
process.stdout.write(text);
try {
  const common = sh("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  if (common) { mkdirSync(join(common, "pi-factory"), { recursive: true }); writeFileSync(join(common, "pi-factory", "report.txt"), text); }
} catch {}
