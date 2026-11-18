// B8: CHEATSHEET.md named /factory-deps, and pi said it had no such command:
// the session had been started before the prompt was added. Pre-flight checks
// that every prompt the docs name exists, and says to restart pi when the
// prompts are newer than the pi process doctor runs under.
// Run: node --test tests/prompts-check.test.mjs
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { namedPrompts, missingPrompts, parseEtime, isPi, newestPrompt } from "../scripts/factory/prompts-check.mjs";

const root = mkdtempSync(join(tmpdir(), "factory-prompts-"));
after(() => rmSync(root, { recursive: true, force: true }));
const script = new URL("../scripts/factory/prompts-check.mjs", import.meta.url).pathname;

// A package as it was for deps-node-22: the CHEATSHEET names /factory-deps,
// the prompts folder doesn't have it yet.
const pkg = join(root, "pkg"), prompts = join(pkg, ".pi/prompts");
mkdirSync(join(pkg, "docs/agents"), { recursive: true }); mkdirSync(prompts, { recursive: true });
writeFileSync(join(pkg, "CHEATSHEET.md"), "| `/factory <mission>` | run |\n| `/factory-deps <mission> \"<what>\"` | deps |\n| `/factory-approve`| ok |\n");
writeFileSync(join(pkg, "docs/agents/factory.md"), "Ask with `/factory-decide m \"x\"`. The guard is `.pi/extensions/factory-guard.ts`; see /factory-guard.\n");
writeFileSync(join(pkg, "docs/adr.md"), "History: `/factory-old` was renamed.\n");
mkdirSync(join(pkg, "docs/adr")); writeFileSync(join(pkg, "docs/adr/ADR.md"), "`/factory-gone` in a decision record.\n");
for (const p of ["factory", "factory-approve", "factory-decide"]) writeFileSync(join(prompts, `${p}.md`), "x\n");

test("the prompts the docs name in backticks, ADRs and proposals left out", () => {
  assert.deepEqual([...namedPrompts(pkg, prompts).keys()].sort(),
    ["factory", "factory-approve", "factory-decide", "factory-deps", "factory-old"]);
});

test("a named prompt with no file under .pi/prompts is reported with the file naming it (B8)", () => {
  assert.deepEqual(missingPrompts(pkg, prompts), [
    { name: "factory-deps", file: "CHEATSHEET.md" },
    { name: "factory-old", file: "docs/adr.md" },
  ]);
  const r = spawnSync("node", [script, pkg, prompts], { encoding: "utf8", env: { ...process.env, PROMPTS_CHECK_PI_STARTED_MS: "" } });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^missing\t\/factory-deps\tCHEATSHEET\.md$/m);
});

test("prompts newer than the running pi: restart pi (B8)", () => {
  writeFileSync(join(prompts, "factory-deps.md"), "x\n"); writeFileSync(join(prompts, "factory-old.md"), "x\n");
  const t = Date.now() / 1000 - 3600;
  for (const p of ["factory", "factory-approve", "factory-decide", "factory-old"]) utimesSync(join(prompts, `${p}.md`), t, t);
  assert.equal(newestPrompt(prompts).name, "factory-deps.md");
  const started = String(Date.now() - 600000);   // pi started ten minutes ago, factory-deps.md written now
  const out = execFileSync("node", [script, pkg, prompts], { encoding: "utf8", env: { ...process.env, PROMPTS_CHECK_PI_STARTED_MS: started } });
  assert.match(out, /^stale\tfactory-deps\.md\t/m);
  const old = String(Date.now() + 60000);         // pi started after every prompt
  assert.equal(execFileSync("node", [script, pkg, prompts], { encoding: "utf8", env: { ...process.env, PROMPTS_CHECK_PI_STARTED_MS: old } }), "");
});

test("ps elapsed time and the pi process, as ps prints them on Linux and macOS", () => {
  assert.equal(parseEtime("05:09"), 309);
  assert.equal(parseEtime("  01:02:03"), 3723);
  assert.equal(parseEtime("2-01:00:00"), 176400);
  assert.equal(parseEtime("junk"), null);
  assert.ok(isPi("pi"));
  assert.ok(isPi("node /opt/homebrew/bin/pi --model x"));
  assert.ok(isPi("/usr/local/bin/pi"));
  assert.ok(!isPi("bash -c scripts/factory/doctor.sh --quick"));
  assert.ok(!isPi("node /usr/lib/pipeline.js pi"));
});
