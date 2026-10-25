#!/usr/bin/env node
// The machine and the gateway, checked the way a mission will use them (D102).
// Onboarding the first project on the installed package found each of these
// by hand, at a red prompt; every one is a fact a script can read.
//
// Usage: node scripts/factory/env-check.mjs [--strict] [--json]
//   --strict   an agent without a model is an error (doctor, setup); without
//              it, a warning (the pre-flight: a maintenance mission never calls
//              the designer, and must not be blocked by it)
//   --json     one object per finding: { level: ok|warn|bad, check, text }
// Exit 1 when a finding is "bad".
//
// Reads FACTORY_GATEWAY_PROD_RE (environment, else .factory/commands.env): a
// regular expression matched against each agent's provider URL and model id.
// A match is a production route: every round of that role spends its quota.
// Without it, a host that looks like production ("prod", "production") is
// flagged as a guess.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { effectiveAgents, PACKAGE_ROOT } from "./effective-models.mjs";
import { gatewayOf } from "./models-probe.mjs";

const strict = process.argv.includes("--strict");
const asJson = process.argv.includes("--json");
const out = [];
const add = (level, check, text) => out.push({ level, check, text });

const setting = (name) => {
  if (process.env[name] !== undefined) return process.env[name];
  let v;
  try {
    for (const line of readFileSync(".factory/commands.env", "utf8").split("\n")) {
      const m = line.match(new RegExp(`^\\s*(?:export\\s+)?${name}=(.*)$`));
      if (m) v = m[1].trim().replace(/^(["'])(.*)\1$/, "$2");
    }
  } catch {}
  return v ?? "";
};

// 1. Commands the factory's scripts call. head has a fallback in lib.sh.
const has = (c) => { try { execFileSync("/bin/sh", ["-c", `command -v ${c}`], { stdio: "ignore" }); return true; } catch { return false; } };
const required = ["git", "node", "bash", "sed", "awk", "grep", "cut", "tr", "wc", "sort", "uniq", "mktemp", "find", "xargs", "diff", "cat", "tail", "dirname", "basename"];
const missing = required.filter((c) => !has(c));
if (!has("sha256sum") && !has("shasum")) missing.push("sha256sum or shasum");
if (missing.length) add("bad", "tools", `missing on this machine: ${missing.join(", ")} (the factory's scripts call them)`);
else add("ok", "tools", "the commands the factory's scripts call are on the PATH");
if (!has("head")) add("warn", "tools", "head is missing: the factory uses its own stand-in (lib.sh); your own shell has none");

// 2. Models: none missing, none floating.
const agents = effectiveAgents();
const unset = agents.filter((a) => !a.model || /[<>]/.test(a.model)).map((a) => a.name);
if (unset.length) add(strict ? "bad" : "warn", "models", `no model on this machine for ${unset.join(", ")}: add them to ~/.pi-factory/models.json, then factory models apply --user`);
else add("ok", "models", `every factory agent has a model (${agents.length})`);
const FLOATING = /(^|[\/:._-])(latest|current|default|stable|preview)$/i;
const floating = agents.filter((a) => a.model && FLOATING.test(a.model));
if (floating.length) {
  const byModel = {};
  for (const a of floating) (byModel[a.model] ??= []).push(a.name);
  for (const [m, names] of Object.entries(byModel))
    add("warn", "models", `${m} is a floating alias (${names.join(", ")}): the gateway can change the model behind it without the id changing, so the probe stamp, the archive and benchmark comparisons can't see it; pin a version`);
}

// 3. Routes: which roles spend a production quota.
const prodRe = setting("FACTORY_GATEWAY_PROD_RE");
let re = null;
if (prodRe) { try { re = new RegExp(prodRe, "i"); } catch { add("bad", "routes", `FACTORY_GATEWAY_PROD_RE is not a valid regular expression: ${prodRe}`); } }
const GUESS = /(^|[^a-z])(prod|production)([^a-z]|$)/i;
const routes = {};
for (const a of agents) {
  if (!a.model || /[<>]/.test(a.model)) continue;
  const g = gatewayOf(a.model);
  if (!g.base) continue;
  let host = g.base; try { host = new URL(g.base).host; } catch {}
  const hit = re ? re.test(g.base) || re.test(a.model) : GUESS.test(host);
  if (hit) (routes[host] ??= []).push(a.name);
}
for (const [host, names] of Object.entries(routes))
  add("warn", "routes", re
    ? `${names.join(", ")} go through ${host}, a production route (FACTORY_GATEWAY_PROD_RE): every round of these roles spends its quota`
    : `${names.join(", ")} go through ${host}, which looks like production: every round of these roles would spend its quota (set FACTORY_GATEWAY_PROD_RE in .factory/commands.env to make this exact)`);
if (re && !Object.keys(routes).length) add("ok", "routes", "no factory agent on a production route");

// 4. TLS.
if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === "0")
  add("warn", "tls", "NODE_TLS_REJECT_UNAUTHORIZED=0: certificate checks are off for every Node process, gateway calls and their key included; trust your company's certificate authority with NODE_EXTRA_CA_CERTS=<ca.pem> and unset it");

// 5. The factory's own checkout.
try {
  const dirty = execFileSync("git", ["-C", PACKAGE_ROOT, "status", "--porcelain", "--untracked-files=no", "--", "."], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  if (dirty) add("warn", "factory", `the factory checkout (${PACKAGE_ROOT}) has local changes: what runs here is not the commit CI runs (${dirty.split("\n").length} file(s))`);
} catch {}
if (existsSync(".factory/package-dir"))
  add("ok", "factory", `the factory is the folder ${readFileSync(".factory/package-dir", "utf8").trim()}/ of its repository; CI links that folder`);

if (asJson) console.log(JSON.stringify(out));
else for (const f of out) console.log(`  ${{ ok: "✓", warn: "!", bad: "✗" }[f.level]} ${f.text}`);
process.exit(out.some((f) => f.level === "bad") ? 1 : 0);
