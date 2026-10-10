#!/usr/bin/env node
// Reads the files a git patch touches, both sides, the way git writes them:
// plain or C-quoted paths ("a/\303\251.txt"), renames, copies, modes. Used by
// the patch guard (D51) and to make monorepo patches project-relative (D56).
//
//   node patch-paths.mjs list <patch>
//       one line per file: status, old, new, new mode, separated by \x1f
//       status: A added, D deleted, M modified, R renamed, C copied
//   node patch-paths.mjs project <in> <out> <prefix> <repo-root> <project-dir>
//       rewrites root-relative paths to project-relative; exit 3 when a file
//       is outside the project
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export function unquote(s) {
  if (!s.startsWith('"')) return s;
  const bytes = [];
  for (let i = 1; i < s.length - 1; i++) {
    const c = s[i];
    if (c !== "\\") { bytes.push(...Buffer.from(c, "utf8")); continue; }
    const n = s[++i];
    if (/[0-7]/.test(n)) { bytes.push(parseInt(s.substr(i, 3), 8)); i += 2; }
    else bytes.push({ n: 10, t: 9, r: 13, '"': 34, "\\": 92, a: 7, b: 8, f: 12, v: 11 }[n] ?? n.charCodeAt(0));
  }
  return Buffer.from(bytes).toString("utf8");
}

export function quote(s) {
  if (!/["\\\x00-\x1f\x7f]|[^\x00-\x7f]/.test(s)) return s;
  let out = '"';
  for (const b of Buffer.from(s, "utf8")) {
    if (b === 34) out += '\\"'; else if (b === 92) out += "\\\\";
    else if (b === 9) out += "\\t"; else if (b === 10) out += "\\n";
    else if (b < 32 || b >= 127) out += "\\" + b.toString(8).padStart(3, "0");
    else out += String.fromCharCode(b);
  }
  return out + '"';
}

// "a/x b/x" or quoted forms → [old, new] without the a/ b/ prefixes.
function gitLinePaths(rest) {
  const tok = [];
  for (let i = 0; i < rest.length;) {
    if (rest[i] === " ") { i++; continue; }
    if (rest[i] === '"') {
      let j = i + 1;
      while (j < rest.length && !(rest[j] === '"' && rest[j - 1] !== "\\")) j++;
      tok.push(unquote(rest.slice(i, j + 1))); i = j + 1;
    } else if (tok.length === 0 && !rest.includes('"')) {
      // unquoted, possibly with spaces: both halves are the same length for a non-rename
      const len = (rest.length - 5) / 2;
      return [rest.slice(2, 2 + len), rest.slice(5 + len)];
    } else { const j = rest.indexOf(" ", i); const e = j < 0 ? rest.length : j; tok.push(rest.slice(i, e)); i = e; }
  }
  return tok.map((t) => t.replace(/^[ab]\//, ""));
}

const side = (v) => { const p = unquote(v.trim()); return p === "/dev/null" ? null : p.replace(/^[ab]\//, ""); };

// Parses a patch into blocks; each keeps its header line indexes for rewriting.
export function parse(text) {
  const lines = text.split("\n");
  const files = [];
  let cur = null, inHeader = false;
  lines.forEach((l, i) => {
    if (l.startsWith("diff --git ")) {
      const [o, n] = gitLinePaths(l.slice(11));
      cur = { status: "M", old: o, new: n, mode: "", header: [i] }; files.push(cur); inHeader = true; return;
    }
    if (!cur || !inHeader) return;
    if (l.startsWith("@@") || l.startsWith("GIT binary patch") || l.startsWith("Binary files ")) { inHeader = false; return; }
    cur.header.push(i);
    let m;
    if ((m = l.match(/^new file mode (\d+)/))) { cur.status = "A"; cur.mode = m[1]; }
    else if ((m = l.match(/^new mode (\d+)/))) cur.mode = m[1];
    else if (l.startsWith("deleted file mode")) cur.status = "D";
    else if ((m = l.match(/^(rename|copy) from (.*)$/))) { cur.status = m[1] === "rename" ? "R" : "C"; cur.old = unquote(m[2]); }
    else if ((m = l.match(/^(rename|copy) to (.*)$/))) cur.new = unquote(m[2]);
    else if (l.startsWith("--- ")) { const p = side(l.slice(4)); if (p) cur.old = p; }
    else if (l.startsWith("+++ ")) { const p = side(l.slice(4)); if (p) cur.new = p; }
  });
  for (const f of files) { if (f.status === "A") f.old = null; if (f.status === "D") f.new = null; }
  return { lines, files };
}

function project(inp, out, prefix, top, dir) {
  const pre = prefix + "/";
  const { lines, files } = parse(readFileSync(inp, "utf8"));
  const paths = (f) => [f.old, f.new].filter(Boolean);
  const all = files.flatMap(paths);
  const rooted = all.filter((p) => p.startsWith(pre)).length;
  if (rooted && rooted < all.length) return 3;              // some files outside the project
  if (!rooted) {
    // Already project-relative, unless it names something that exists at the
    // repo root and not in the project (a sibling project, a root folder).
    for (const p of all) {
      const first = p.split("/")[0];
      if (existsSync(join(top, first)) && !existsSync(join(dir, first))) return 3;
    }
    writeFileSync(out, lines.join("\n")); return 0;
  }
  const strip = (p) => p.slice(pre.length);
  for (const f of files) {
    const o = f.old && strip(f.old), n = f.new && strip(f.new);
    for (const i of f.header) {
      const l = lines[i];
      if (l.startsWith("diff --git ")) lines[i] = `diff --git ${quote("a/" + (o ?? n))} ${quote("b/" + (n ?? o))}`;
      else if (l.startsWith("--- ") && f.old) lines[i] = `--- ${quote("a/" + o)}`;
      else if (l.startsWith("+++ ") && f.new) lines[i] = `+++ ${quote("b/" + n)}`;
      else if (/^(rename|copy) from /.test(l)) lines[i] = l.replace(/ from .*$/, ` from ${quote(o)}`);
      else if (/^(rename|copy) to /.test(l)) lines[i] = l.replace(/ to .*$/, ` to ${quote(n)}`);
    }
  }
  writeFileSync(out, lines.join("\n"));
  return 0;
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd === "list") {
  for (const f of parse(readFileSync(args[0], "utf8")).files) process.stdout.write([f.status, f.old ?? "", f.new ?? "", f.mode].join("\x1f") + "\n");
} else if (cmd === "project") {
  process.exit(project(...args));
} else if (cmd) {
  console.error("usage: patch-paths.mjs list <patch> | project <in> <out> <prefix> <repo-root> <project-dir>"); process.exit(2);
}
