// B13 (P20): prompt caching was invisible. Every archived run of one model
// family read 0 tokens from cache while the others read 5 to 20 times their
// fresh input from it; a contract author paid $13.06 for 2.1M uncached input
// tokens and nothing said so. The shapes below are the archived run.json usage
// of that mission's runs, with run ids and model names anonymized.
// Run: node --test tests/cache.test.mjs
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { cacheShare, cacheByModel, modelOf, scanArchive } from "../scripts/factory/cache.mjs";

const root = mkdtempSync(join(tmpdir(), "factory-cache-"));
after(() => rmSync(root, { recursive: true, force: true }));

// As archived (abandon-timeout, deps-node-22, error-codes-970): agent, model, usage.
const runs = [
  ["m1", "a1_factory-contract-author", "gw/vendor-a/big-1:high", { input: 2113846, output: 30000, cacheRead: 0, cacheWrite: 0, turns: 51, cost: 13.06 }],
  ["m1", "a2_factory-worker-heavy", "gw/vendor-a/mid-1:high", { input: 1819615, output: 28575, cacheRead: 0, cacheWrite: 0, turns: 51, cost: 3.92 }],
  ["m2", "a3_factory-contract-author", "gw/vendor-a/big-1:high", { input: 176334, output: 4000, cacheRead: 0, cacheWrite: 0, turns: 10, cost: 0.89 }],
  ["m2", "a4_factory-reviewer", "gw/vendor-b/rev-1:high", { input: 57, output: 2000, cacheRead: 560131, cacheWrite: 60811, turns: 19, cost: 0.31 }],
  ["m2", "a5_factory-worker", "gw/vendor-c/fast-1:medium", { input: 22514, output: 3000, cacheRead: 700928, cacheWrite: 0, turns: 32, cost: 0.02 }],
  ["m2", "a6_factory-review-axis", "gw/vendor-b/axis-1:medium", { input: 6, output: 300, cacheRead: 2518, cacheWrite: 5867, turns: 2, cost: 0.01 }],
];
for (const [m, dir, model, usage] of runs) {
  mkdirSync(join(root, m, dir), { recursive: true });
  const [run, agent] = dir.split("_");
  writeFileSync(join(root, m, dir, "run.json"), JSON.stringify({ run, agent, model, usage }));
}
// A run archived before usage was recorded, and a stray file: both ignored.
mkdirSync(join(root, "m2", "a7_factory-worker")); writeFileSync(join(root, "m2", "a7_factory-worker", "run.json"), "{}");
writeFileSync(join(root, "m2", "metrics.json"), "{}");

test("cacheShare: the part of a run's input read from cache; none without input", () => {
  assert.equal(cacheShare({ input: 2113846, cacheRead: 0, cacheWrite: 0 }).share, 0);
  const r = cacheShare({ input: 22514, cacheRead: 700928, cacheWrite: 0 });
  assert.equal(Math.round(r.share * 100), 97); assert.equal(r.total, 723442);
  assert.equal(cacheShare({}).share, null);
});

test("modelOf: one model whatever its thinking level", () => {
  assert.equal(modelOf("gw/vendor-a/big-1:high"), "gw/vendor-a/big-1");
  assert.equal(modelOf("gw/vendor-a/big-1"), "gw/vendor-a/big-1");
});

test("cacheByModel: the share per model, and a model whose runs never read from cache over several turns is named", () => {
  const ms = cacheByModel(scanArchive(root));
  const big = ms.find((m) => m.model === "gw/vendor-a/big-1");
  assert.deepEqual([big.runs, big.turns, big.cacheRead, big.share, big.noCache], [2, 61, 0, 0, true]);
  // One run without cache is not enough to name a model.
  assert.equal(ms.find((m) => m.model === "gw/vendor-a/mid-1").noCache, false);
  const rev = ms.find((m) => m.model === "gw/vendor-b/rev-1");
  assert.equal(rev.noCache, false); assert.ok(rev.share > 0.8);
  assert.equal(ms.filter((m) => m.noCache).length, 1);
});

test("cache.mjs --warn: one line per model that never reads from cache, naming the model; silent otherwise", () => {
  const out = execFileSync("node", ["scripts/factory/cache.mjs", "--warn", root], { encoding: "utf8" });
  assert.match(out, /gw\/vendor-a\/big-1: 2 runs, 61 turns, 2\.29M input, none read from cache/);
  assert.doesNotMatch(out, /vendor-b|vendor-c|mid-1/);
  const clean = mkdtempSync(join(tmpdir(), "factory-cache-clean-"));
  try { assert.equal(execFileSync("node", ["scripts/factory/cache.mjs", "--warn", clean], { encoding: "utf8" }), ""); }
  finally { rmSync(clean, { recursive: true, force: true }); }
});

test("cache.mjs: the share per model, every archived mission", () => {
  const out = execFileSync("node", ["scripts/factory/cache.mjs", root], { encoding: "utf8" });
  assert.match(out, /gw\/vendor-a\/big-1 +2 +61 +2\.29M +0 +0%/);
  assert.match(out, /gw\/vendor-c\/fast-1 +1 +32 +723\.4k +700\.9k +97%/);
});

test("tokens.mjs: each run's cache share, and the share per model", () => {
  const out = execFileSync("node", ["scripts/factory/tokens.mjs", join(root, "m2")], { encoding: "utf8" });
  assert.match(out, /a3 +contract-author +176\.3k +0% from cache/);
  assert.match(out, /a5 +worker +723\.4k +97% from cache/);
  assert.match(out, /Cache by model/); assert.match(out, /gw\/vendor-b\/rev-1 +1 +19/);
  const j = JSON.parse(execFileSync("node", ["scripts/factory/tokens.mjs", join(root, "m2"), "--json"], { encoding: "utf8" }));
  assert.equal(j.runs.find((r) => r.run === "a5").cacheShare, 0.97);
  assert.ok(Array.isArray(j.models) && j.models.length === 4);
});
