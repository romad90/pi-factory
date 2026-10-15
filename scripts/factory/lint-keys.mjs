#!/usr/bin/env node
// Turns lint output into one key per error, stable across line shifts (D62):
// "<file>: <message>" with line and column numbers removed, the project path
// made relative. Reads stdin, prints sorted keys. Used to compare a lint run
// against .factory/lint-baseline.txt, so only new errors fail integration.
//
//   <lint command> 2>&1 | node lint-keys.mjs [project-dir]
//
// Understands one-line formats (eslint unix/compact, tsc, ruff, flake8,
// golangci-lint: "path:line:col: … error …") and eslint's default "stylish"
// format (a file line, then "  12:5  error  message  rule"). An error line is
// one matching FACTORY_LINT_ERROR_RE (default: the word "error", any case).
import { readFileSync } from "node:fs";

const dir = (process.argv[2] || process.cwd()).replace(/\/$/, "") + "/";
const re = new RegExp(process.env.FACTORY_LINT_ERROR_RE || "(^|[^A-Za-z])error([^A-Za-z]|$)", "i");
const keys = [];
let file = "";
for (let line of readFileSync(0, "utf8").split("\n")) {
  line = line.replace(/\x1b\[[0-9;]*m/g, "").replaceAll(dir, "").trimEnd();
  if (!line) continue;
  const stylish = line.match(/^\s+\d+:\d+\s+error\s+(.*)$/i);
  if (stylish) { keys.push(`${file}: ${stylish[1].replace(/\s{2,}/g, " ")}`); continue; }
  if (/^\s*(✖|×|Found \d+|\d+ (problems?|errors?)\b)/i.test(line)) continue;  // summaries ("✖ 3 problems", "Found 2 errors")
  if (/^\S/.test(line) && !/:\s|:\d+|\(\d+,\d+\)/.test(line)) { file = line.trim(); continue; }  // stylish file header
  if (!re.test(line)) continue;
  keys.push(line.replace(/:\d+(:\d+)?(?=[:\s]|$)/g, "").replace(/\(\d+,\d+\)/g, "").replace(/\s{2,}/g, " ").trim());
}
process.stdout.write(keys.sort().map((k) => k + "\n").join(""));
