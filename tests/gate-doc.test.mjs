// The gate page (D130): everything a person reads to decide G1, from the
// mission's own files, on the eslint-10 records as they were at G1.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, cpSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { parseContract, gateDoc } from "../scripts/factory/gate-doc.mjs";

const FIX = new URL("./fixtures/gate/", import.meta.url).pathname;
const spec = readFileSync(join(FIX, "eslint-10/spec.md"), "utf8");

test("parseContract: every assertion with its fields, in order, and what the contract leaves out", () => {
  const c = parseContract(spec);
  assert.equal(c.assertions.length, 14);
  assert.deepEqual(c.assertions.slice(0, 3).map((a) => a.id), ["VAL-DEPS-001", "VAL-DEPS-002", "VAL-DEPS-003"]);
  const conf = c.assertions.find((a) => a.id === "VAL-CONF-001");
  assert.equal(conf.title, "Today's two extra rules and CommonJS apply where they did");
  assert.equal(conf.kind, "behavior");
  assert.match(conf.given, /^the checkout after `npm ci`/);
  assert.match(conf.when, /once for each of the 58 files/);
  assert.match(conf.then, /exactly six keys:\n\s+- `vars`: `"all"`/);
  assert.match(conf.then, /no `varsIgnorePattern` key/);
  assert.match(conf.evidence, /58 `--print-config` outputs/);
  assert.match(conf.amended, /^2026-11-10, critique findings 1 and 2/);
  assert.equal(c.assertions.find((a) => a.id === "VAL-DEPS-002").kind, "code");
  assert.match(c.preamble, /^The base commit is `adc39d7`/);
  assert.match(c.notCovered, /The GitHub Actions lint job/);
  assert.equal(c.approved, "");
  assert.match(c.specBody, /^# eslint-10/);
  assert.doesNotMatch(c.specBody, /## Validation contract/);
});

test("gateDoc: the critique's findings point at their assertions, and each assertion lists the findings that name it", () => {
  const d = gateDoc(FIX, "eslint-10");
  assert.equal(d.mission, "eslint-10");
  assert.equal(d.critique.result, "FINDINGS");
  assert.equal(d.critique.findings.length, 3);
  assert.match(d.critique.traceability, /^\| Spec requirement \| Assertions \| Status \|/);
  assert.match(d.critique.limits, /I did not install dependencies/);
  const byId = Object.fromEntries(d.contract.assertions.map((a) => [a.id, a]));
  assert.deepEqual(byId["VAL-CONF-001"].findings, ["1", "2"]);
  assert.deepEqual(byId["VAL-DEPS-001"].findings, []);
  assert.equal(d.amendments.length, 1);
  assert.match(d.amendments[0].text, /^Critique findings 1 and 2/);
  assert.equal(d.amendments[0].status, "sent 2026-11-10");
  assert.equal(d.decisions.length, 1);
  assert.equal(d.decisions[0].kind, "amend");
  assert.equal(typeof d.critiqueAfterContract, "boolean");
});

test("gateDoc: a missing critique is null, secrets are redacted, and names outside the mission folder are refused", () => {
  const root = mkdtempSync(join(tmpdir(), "gate-"));
  mkdirSync(join(root, "m1"));
  writeFileSync(join(root, "m1", "spec.md"), "# m1\n\nexport DB_PASSWORD=hunter2\n");
  const d = gateDoc(root, "m1");
  assert.equal(d.critique, null);
  assert.doesNotMatch(d.contract.specBody, /hunter2/);
  for (const bad of ["..", "../x", ".hidden", "a/b", ""]) assert.equal(gateDoc(root, bad), null, bad);
  assert.equal(gateDoc(root, "nope"), null);
});

test("the command line prints the same JSON, and exits 1 when the mission has no spec", () => {
  const cli = new URL("../scripts/factory/gate-doc.mjs", import.meta.url).pathname;
  const out = JSON.parse(execFileSync(process.execPath, [cli, FIX, "eslint-10"], { encoding: "utf8" }));
  assert.equal(out.contract.assertions.length, 14);
  assert.throws(() => execFileSync(process.execPath, [cli, FIX, "nope"], { stdio: "ignore" }));
});

test("parseContract: a spec without the contract heading still yields its assertions (older specs)", () => {
  const c = parseContract("# x\n\n### VAL-A-001: one\n- **Given:** g\n- **Kind:** code\n\n### VAL-A-002 two\n- **Given:** h\n");
  assert.deepEqual(c.assertions.map((a) => [a.id, a.title, a.given, a.kind]), [["VAL-A-001", "one", "g", "code"], ["VAL-A-002", "two", "h", ""]]);
  assert.equal(c.preamble, "");
  const old = parseContract("## Validation contract\n\n### VAL-B-001: greets\n**Kind:** behavior\nGiven a user, when they say hi, then hello.\n");
  assert.deepEqual([old.assertions[0].kind, old.assertions[0].given], ["behavior", "Given a user, when they say hi, then hello."]);
});
