#!/usr/bin/env node
// The gate page (D130): what a person reads to decide G1, from the mission's
// own files, so the cockpit shows the contract and its critique instead of
// a file name. Read-only, served on demand by cockpit.sh (gate.json), never in
// the snapshot.
//
// Usage: node gate-doc.mjs <missions-dir> <mission>
//   Prints JSON; exits 1 when the mission has no spec.md.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { parseCritique } from "./cockpit-contract.mjs";
import { redact } from "./redact.mjs";

const SAFE = /^\w[\w.-]*$/;
const read = (f) => { try { return readFileSync(f, "utf8"); } catch { return null; } };
const mtime = (f) => { try { return statSync(f).mtimeMs; } catch { return 0; } };

// "## Name" sections of a Markdown file, by name.
function sections(t) {
  const out = {}, re = /^## +(.+)$/gm, at = [];
  let m; while ((m = re.exec(t))) at.push({ name: m[1].trim(), head: m.index, start: re.lastIndex });
  at.forEach((a, i) => { out[a.name] = t.slice(a.start, i + 1 < at.length ? at[i + 1].head : undefined).trim(); });
  return out;
}

// One assertion's "- **Field:** value" lines; a value runs on over indented or
// blank lines (a nested list, a second paragraph) until the next field.
function fields(body) {
  const out = {}; let cur = null;
  for (const line of body.split("\n")) {
    const f = line.match(/^(?:- )?\*\*([A-Za-z][\w ]*):\*\*\s?(.*)$/);
    if (f) { cur = f[1].toLowerCase(); out[cur] = f[2]; continue; }
    if (cur) out[cur] += "\n" + line;
  }
  for (const k of Object.keys(out)) out[k] = out[k].replace(/\s+$/, "");
  return out;
}

export function parseContract(spec) {
  const at = spec.search(/^## +Validation contract\s*$/m);
  const specBody = (at < 0 ? spec : spec.slice(0, at)).trim();
  // No heading (an older spec): the assertions are wherever they are.
  let c = at < 0 ? spec : spec.slice(at).replace(/^## +Validation contract\s*\n/, "");
  const next = at < 0 ? -1 : c.search(/^## /m); if (next >= 0) c = c.slice(0, next);
  const approved = (c.match(/^\*\*Contract approved:\*\*\s*(.+)$/m) || [])[1]?.trim() || "";
  const heads = [], re = /^### +(.+)$/gm;
  let m; while ((m = re.exec(c))) heads.push({ text: m[1].trim(), head: m.index, start: re.lastIndex });
  const preamble = at < 0 ? "" : c.slice(0, heads.length ? heads[0].head : undefined).replace(/^\*\*Contract approved:\*\*.*$/m, "").trim();
  const assertions = []; let notCovered = "";
  heads.forEach((h, i) => {
    const body = c.slice(h.start, i + 1 < heads.length ? heads[i + 1].head : undefined).trim();
    const id = h.text.match(/^(VAL-[A-Z0-9]+-\d{3}):?\s*(.*)$/);
    if (id) {
      const f = fields(body);
      // An older contract writes "**Kind:** …" and a prose line "Given …, when …".
      assertions.push({ id: id[1], title: id[2], given: f.given || (body.split("\n").find((l) => /^Given\b/i.test(l.trim())) || "").trim(), when: f.when || "", then: f.then || "", evidence: f.evidence || "",
        kind: (f.kind || "").trim().split(/\s+/)[0] || "", amended: f.amended || "", unchecked: /\(unchecked\)/i.test(body) });
    } else if (/^not covered/i.test(h.text)) notCovered = body;
  });
  return { specBody, preamble, approved, assertions, notCovered };
}

export function gateDoc(root, mission) {
  if (!SAFE.test(mission || "") || mission.includes("..")) return null;
  const dir = join(root, mission), specFile = join(dir, "spec.md");
  const spec = read(specFile); if (spec === null) return null;
  const contract = parseContract(redact(spec));
  const ct = read(join(dir, "contract-critique.md"));
  let critique = null;
  if (ct !== null) {
    const t = redact(ct), s = sections(t);
    critique = { ...parseCritique(t), traceability: s["Traceability: spec → contract"] || s.Traceability || "", checklist: s.Checklist || "", limits: s["Review limits"] || "" };
    for (const a of contract.assertions) a.findings = critique.findings.filter((f) => f.refs.includes(a.id)).map((f) => f.id);
  } else for (const a of contract.assertions) a.findings = [];
  let amendments = [];
  try {
    amendments = readdirSync(join(dir, "amendments")).filter((f) => f.endsWith(".md")).sort().map((f) => {
      const t = redact(read(join(dir, "amendments", f)) || "");
      return { file: f, status: (t.match(/^\*\*Status:\*\*\s*(.+)$/m) || [])[1]?.trim() || "",
        text: t.replace(/^#.*$/m, "").replace(/^\*\*[A-Za-z ]+:\*\*.*$/gm, "").trim() };
    });
  } catch {}
  const tsv = read(join(dir, "decisions.tsv")) || "";
  const [head, ...rows] = tsv.split("\n").filter(Boolean);
  const cols = (head || "").split("\t");
  const decisions = rows.map((r) => Object.fromEntries(r.split("\t").map((v, i) => [cols[i] || `c${i}`, redact(v)])));
  return { mission, contract, critique, critiqueAfterContract: ct !== null && mtime(join(dir, "contract-critique.md")) >= mtime(specFile), amendments, decisions };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const d = gateDoc(process.argv[2] || ".scratch", process.argv[3] || "");
  if (!d) { console.error("gate-doc: no such mission (or no spec.md)"); process.exit(1); }
  process.stdout.write(JSON.stringify(d));
}
