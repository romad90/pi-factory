// D127: the Node that runs the checks matches what the project says it runs on.
// Run: node --test tests/node-version.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { check, satisfies } from "../scripts/factory/node-version.mjs";

test("ranges the projects use", () => {
  const cases = [
    ["v26.13.0", ">=22", true], ["v20.11.1", ">=22", false], ["v22.23.4", "^22.13.0 || >=24", true], ["v23.1.0", "^22.13.0 || >=24", false],
    ["v20.19.0", "20 || >=22", true], ["v21.0.0", "20 || >=22", false], ["v22.1.0", "22.x", true], ["v18.0.0", ">= 18 < 21", true],
    ["v22.0.0", ">= 18 < 21", false], ["v16.20.2", "~16.20", true], ["v16.19.0", "~16.20", false], ["v22.0.0", "lts/*", null],
  ];
  for (const [v, r, want] of cases) assert.equal(satisfies(v, r), want, `${v} vs ${r}`);
});

test("engines.node first, then .nvmrc; a mismatch says what to do", () => {
  const d = mkdtempSync(join(tmpdir(), "nv-"));
  assert.equal(check(d, "v26.13.0")[0], "unknown");
  writeFileSync(join(d, ".nvmrc"), "22\n");
  assert.deepEqual(check(d, "v26.13.0")[0], "mismatch");
  assert.equal(check(d, "v22.23.4")[0], "ok");
  writeFileSync(join(d, "package.json"), JSON.stringify({ engines: { node: ">=22" } }));
  const [s, why] = check(d, "v26.13.0");
  assert.equal(s, "ok", "deps-node-22: Node 26 under engines >=22 is fine");
  assert.match(why, /package.json engines.node ">=22"/);
  assert.match(check(d, "v20.11.1")[1], /doesn't match package.json engines.node ">=22".*nvm use/);
});
