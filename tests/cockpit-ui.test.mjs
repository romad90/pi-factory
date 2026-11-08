// The cockpit, driven like a person (D123): each question asked in chat
// during the gym missions must be answered on the page within two clicks,
// on the gym's real records (tests/fixtures/cockpit-gym.json, scrubbed by
// scripts/dev/cockpit-fixture.mjs). And every page renders in under 100 ms
// with 50 missions.
// Run: node --test tests/cockpit-ui.test.mjs   (needs playwright and its chromium)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { toContract } from "../scripts/factory/cockpit-contract.mjs";

const require = createRequire(import.meta.url);
let chromium = null;
try { ({ chromium } = require("playwright")); } catch { /* skipped below */ }
const skip = chromium ? false : "playwright is not installed (npm i --no-save playwright && npx playwright install chromium)";

const html = readFileSync(new URL("../scripts/factory/cockpit.html", import.meta.url), "utf8");
const gym = JSON.parse(readFileSync(new URL("./fixtures/cockpit-gym.json", import.meta.url), "utf8"));
const MISSION = "server-survives-bad-input", T03 = "03-fix-parser-error-handler-nesting";

// The moment the lead relayed in chat: ticket 03 out of rounds, before the
// heavy worker; the records otherwise as they are.
function atTheStop() {
  const s = structuredClone(gym);
  const m = s.missions.find((x) => x.name === MISSION);
  Object.assign(m, { step: "escalate", human: true, mr: "", next: "human: 03 failed 3 rounds." });
  const t = m.tickets.find((x) => x.name === T03);
  Object.assign(t, { state: "escalate", round: 3, history: t.history.slice(0, 3) });
  m.counts = { total: 3, pass: 2, escalate: 1 };
  return s;
}

let server, browser, snapshot = gym;
before(async () => {
  if (skip) return;
  server = createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    if (u.pathname === "/") { res.writeHead(200, { "content-type": "text/html" }); res.end(html); return; }
    if (u.pathname === "/state.json") { res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify(toContract({ ...snapshot, generated: new Date().toISOString() }))); return; }
    res.writeHead(404); res.end();
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  browser = await chromium.launch();
});
after(async () => { await browser?.close(); server?.close(); });

async function open(snap, hash = "") {
  snapshot = snap;
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
  await page.goto(`http://127.0.0.1:${server.address().port}/${hash}`);
  await page.waitForFunction(() => document.querySelector("#waiting")?.textContent);
  return page;
}

test("\"what are we waiting for?\" is the first thing on every page (0 clicks)", { skip }, async () => {
  const page = await open(atTheStop());
  assert.match(await page.textContent("#waiting"), /Waiting on you.*server-survives-bad-input · 03-fix-parser-error-handler-nesting/);
  await page.click("text=Missions");
  assert.match(await page.textContent("#waiting"), /Waiting on you/);
  const idle = await open(gym);
  assert.match(await idle.textContent("#waiting"), /Idle.*no open mission/);
});

test("the ticket 03 stop is a card on the home page: question, the rounds, the command to copy (0 clicks)", { skip }, async () => {
  const page = await open(atTheStop());
  const card = page.locator(`[data-card="${MISSION}:ticket:${T03}"]`);
  assert.match(await card.textContent(), /failed 3 review rounds/);
  assert.equal(await card.locator(".ev li").count(), 3);
  assert.equal(await card.locator(".opt.sug code").textContent(), `/factory-rereview ${MISSION} ${T03} "<what changed since the review, or why it judged nothing>"`);
});

test("\"where are we?\": a mission with mr.url is Closed, whatever step it last showed (1 click)", { skip }, async () => {
  const page = await open(gym);
  await page.click("text=Missions");
  await page.waitForSelector(".board");
  const closed = page.locator(".col", { has: page.locator("h2", { hasText: "Closed" }) });
  for (const name of ["server-survives-bad-input", "pin-destroy-during-search", "end-issue-845-tests-on-end"]) {
    assert.equal(await closed.locator(`[data-m="${name}"]`).count(), 1, `${name} under Closed`);
  }
  assert.doesNotMatch(await page.textContent(".board"), /needs you\b.*health/i);
});

test("\"why did ticket 03 take four rounds?\": the guard's refusals on the run that made them (2 clicks)", { skip }, async () => {
  const page = await open(gym);
  await page.click("text=Missions");
  await page.waitForSelector(".board");
  await page.click(`[data-m="${MISSION}"]`);
  // The board's strips are svg.tl too: wait for the mission's own timeline.
  const tl = page.locator(".panel", { has: page.locator("h2", { hasText: "Timeline by role" }) }).locator("svg.tl");
  await tl.waitFor();
  assert.equal(await tl.locator("rect.run").count(), 29, "every archived run is a bar");
  const titles = await tl.locator("rect > title").allTextContents();
  const refused = titles.filter((t) => t.startsWith("refused"));
  assert.equal(refused.length, 8);
  assert.ok(titles.some((t) => /^reviewer 8779b383/.test(t) && /3 refused/.test(t)), "the reviewer of ticket 01 carries its 3 refusals");
  assert.ok(titles.some((t) => /^review-axis/.test(t) && /0 refused/.test(t)), "the axes beside it carry none");
});

test("\"which refusals were the guard's fault?\": judged again today, by rule (1 click)", { skip }, async () => {
  const page = await open(gym);
  await page.keyboard.press("h");
  await page.waitForSelector("text=Guard refusals by rule");
  const row = page.locator("tr", { has: page.locator("td", { hasText: /^scratch$/ }) });
  const cells = await row.locator("td").allTextContents();
  assert.deepEqual(cells.slice(0, 3), ["scratch", "8", "4"], "8 scratch refusals, 4 allowed by today's guard (E33, fixed)");
});

test("every page renders in under 100 ms with 50 missions", { skip }, async () => {
  const fifty = structuredClone(gym);
  fifty.missions = Array.from({ length: 50 }, (_, i) => ({ ...structuredClone(gym.missions[i % 3]), name: `${gym.missions[i % 3].name}-${i}` }));
  const page = await open(fifty);
  const times = await page.evaluate(async (name) => {
    const out = {};
    for (const hash of ["#/", "#/missions", `#/m/${name}`, "#/health"]) {
      const runs = [];
      for (let i = 0; i < 5; i++) { history.replaceState(null, "", hash); const t = performance.now(); render(); runs.push(performance.now() - t); }
      out[hash] = runs.sort((a, b) => a - b)[2];
    }
    return out;
  }, `${MISSION}-2`);
  for (const [hash, ms] of Object.entries(times)) assert.ok(ms < 100, `${hash} rendered in ${ms.toFixed(1)} ms`);
  console.log(`render, median of 5, 50 missions: ${Object.entries(times).map(([h, ms]) => `${h} ${ms.toFixed(1)} ms`).join(" · ")}`);
});
