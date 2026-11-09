#!/usr/bin/env node
// Does the Node that runs the checks match what the project says it runs on
// (D127)? package.json's engines.node, then .nvmrc. A worker in deps-node-22
// ran on Node 26 while the contract said 22; nothing said so until a person read
// the journal.
//
// Usage: node node-version.mjs [<project dir>]
// Prints "ok|mismatch|unknown<TAB><sentence>". Exit 0, or 1 on a mismatch.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const parse = (v) => String(v).trim().replace(/^v/, "").split(".").map((x) => (x === "x" || x === "*" || x === "" ? null : Number(x)));
const cmp = (a, b) => { for (let i = 0; i < 3; i++) { const x = a[i] ?? 0, y = b[i] ?? 0; if (x !== y) return x < y ? -1 : 1; } return 0; };

// One comparator against a version: >=, >, <=, <, =, ^, ~, or a bare (partial) version.
function one(c, v) {
  const m = c.match(/^(>=|<=|>|<|=|\^|~)?\s*v?([\dx*]+(?:\.[\dx*]+){0,2})$/);
  if (!m) return null;
  const [op = "", raw] = [m[1], m[2]], r = parse(raw), parts = raw.split(".").length;
  const filled = r.map((x) => x ?? 0);
  switch (op) {
    case ">=": return cmp(v, filled) >= 0;
    case ">": return cmp(v, filled) > 0;
    case "<=": return cmp(v, filled) <= 0;
    case "<": return cmp(v, filled) < 0;
    case "^": return v[0] === filled[0] && cmp(v, filled) >= 0;
    case "~": return v[0] === filled[0] && (parts < 2 || v[1] === filled[1]) && cmp(v, filled) >= 0;
    default: return r.every((x, i) => i >= parts || x === null || v[i] === x);   // "22", "22.x", "=22.1"
  }
}

export function satisfies(version, range) {
  const v = parse(version).map((x) => x ?? 0);
  let known = false;
  for (const alt of String(range).split("||")) {
    const set = alt.trim().split(/\s+/).filter(Boolean).flatMap((c, i, a) => (/^(>=|<=|>|<|=|\^|~)$/.test(c) ? [] : [/^(>=|<=|>|<|=|\^|~)$/.test(a[i - 1]) ? a[i - 1] + c : c]));
    if (!set.length) continue;
    const results = set.map((c) => one(c, v));
    if (results.some((r) => r === null)) continue;
    known = true;
    if (results.every(Boolean)) return true;
  }
  return known ? false : null;
}

export function check(dir, version = process.version) {
  let range = "", from = "";
  try { range = JSON.parse(readFileSync(join(dir, "package.json"), "utf8")).engines?.node || ""; from = "package.json engines.node"; } catch {}
  if (!range) { try { range = readFileSync(join(dir, ".nvmrc"), "utf8").trim().replace(/^v/, ""); from = ".nvmrc"; } catch {} }
  if (!range) return ["unknown", `Node ${version}; the project names no Node version (no engines.node, no .nvmrc)`];
  const ok = satisfies(version, from === ".nvmrc" && /^\d+$/.test(range) ? `${range}.x` : range);
  if (ok === null) return ["unknown", `Node ${version}; ${from} is "${range}", which this check can't read`];
  return ok ? ["ok", `Node ${version} matches ${from} "${range}"`]
    : ["mismatch", `Node ${version} doesn't match ${from} "${range}": tests run here prove nothing about the Node the project runs on. Use a matching Node (nvm use, or install one).`];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [state, sentence] = check(process.argv[2] || ".");
  console.log(`${state}\t${sentence}`);
  process.exit(state === "mismatch" ? 1 : 0);
}
