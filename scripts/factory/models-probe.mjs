#!/usr/bin/env node
// Probes the model gateway with what the factory really sends, before a wave
// spends a round on it (D59). Mission 2 lost two evenings to failures no
// static check could see: a model the gateway refuses (403), a thinking level
// it rejects (400), a message order it rejects after a tool call (400), and a
// quota too small for a worker (429).
//
// Usage: node scripts/factory/models-probe.mjs [--stamp | --hash | --resolvable]
// Each agent's model is probed on its own provider (D79): "provider/id" is
// looked up in Pi's models.json ($PI_CODING_AGENT_DIR or ~/.pi/agent), whose
// baseUrl and apiKey Pi itself uses; an openai-completions provider is probed.
// A model with no such provider falls back to FACTORY_GATEWAY_URL and the key
// in the variable named by FACTORY_GATEWAY_KEY_ENV (default OPENAI_API_KEY).
// Keys are never printed. --resolvable exits 0 when any agent can be probed.
// Spends two small requests per (model, thinking) pair. --stamp writes
// .factory/models-probe.ok so the pre-flight knows these models were probed.
import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";

const AGENTS_DIR = ".pi/agents/factory";
const STAMP = ".factory/models-probe.ok";
import { homedir } from "node:os";
const fallbackBase = (process.env.FACTORY_GATEWAY_URL || "").replace(/\/+$/, "");
const keyEnv = process.env.FACTORY_GATEWAY_KEY_ENV || "OPENAI_API_KEY";
const fallbackKey = process.env[keyEnv] || "";

let failed = false;
const ok = (m) => console.log(`  ✓ ${m}`);
const bad = (m) => { console.log(`  ✗ ${m}`); failed = true; };
const warn = (m) => console.log(`  ! ${m}`);

const field = (text, k) => (text.match(new RegExp(`^${k}:\\s*(.*)$`, "m")) || [])[1]?.trim();
export function agentModels(dir = AGENTS_DIR) {
  return readdirSync(dir).filter((f) => f.endsWith(".md")).map((f) => {
    const fm = (readFileSync(join(dir, f), "utf8").match(/^---\n([\s\S]*?)\n---/) || [])[1] || "";
    return { agent: field(fm, "name") || f, model: field(fm, "model") || "", thinking: field(fm, "thinking") || "off" };
  });
}
// Hash of every (agent, model, thinking): the stamp is valid only for this set.
export function modelsHash(list = agentModels()) {
  return createHash("sha256").update(list.map((a) => `${a.agent}=${a.model}@${a.thinking}`).sort().join("\n")).digest("hex").slice(0, 16);
}
const bareId = (m) => m.replace(/^[^/]+\//, "");          // "provider/id" → "id" as the gateway knows it

// D79: Pi's providers, so two gateways (two keys, two model lists) are each probed.
function piProviders() {
  const f = join(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"), "models.json");
  try { return JSON.parse(readFileSync(f, "utf8")).providers || {}; } catch { return {}; }
}
// Pi's apiKey is an environment variable name or the key itself; "!cmd" can't be resolved here.
const resolveKey = (k) => !k ? "" : k.startsWith("!") ? null : /^[A-Z_][A-Z0-9_]*$/.test(k) ? (process.env[k] || "") : k;
export function gatewayOf(model, providers = piProviders()) {
  const name = model.includes("/") ? model.split("/")[0] : "";
  const p = name && providers[name];
  if (p && p.baseUrl) {
    if (p.api && p.api !== "openai-completions") return { skip: `provider ${name} uses api ${p.api}, not probed` };
    const key = resolveKey(p.apiKey);
    if (key === null) return { skip: `provider ${name} gets its key from a command, not probed` };
    return { name, base: p.baseUrl.replace(/\/+$/, ""), key };
  }
  if (fallbackBase) return { name: "FACTORY_GATEWAY_URL", base: fallbackBase, key: fallbackKey };
  return { skip: "no provider in Pi's models.json and no FACTORY_GATEWAY_URL" };
}

async function call(gw, path, body) {
  const base = gw.base, key = gw.key;
  const res = await fetch(base + path, {
    method: body ? "POST" : "GET",
    headers: { "content-type": "application/json", ...(key ? { authorization: `Bearer ${key}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(60000),
  });
  let text = ""; try { text = await res.text(); } catch {}
  return { status: res.status, headers: res.headers, text, short: text.slice(0, 300) };
}

// The order pi-subagents produces in a worker run: a tool call, its result,
// then a user turn (steering, a reminder). Some providers reject it (400).
function toolTurn(model, thinking) {
  const body = {
    model, max_tokens: 16,
    messages: [
      { role: "user", content: "Call ping." },
      { role: "assistant", content: "", tool_calls: [{ id: "call_1", type: "function", function: { name: "ping", arguments: "{}" } }] },
      { role: "tool", tool_call_id: "call_1", content: "pong" },
      { role: "user", content: "Reply with: ok" },
    ],
    tools: [{ type: "function", function: { name: "ping", description: "health check", parameters: { type: "object", properties: {} } } }],
  };
  if (thinking && thinking !== "off") body.reasoning_effort = thinking;
  return body;
}

function quota(h) {
  const n = (k) => Number(h.get(k)) || 0;
  return { req: n("x-ratelimit-limit-requests"), tok: n("x-ratelimit-limit-tokens") };
}

async function main() {
  console.log("Model probe");
  const agents = agentModels();
  const groups = new Map();                      // base → { gw, agents }
  for (const a of agents) {
    const gw = gatewayOf(a.model);
    if (gw.skip) { console.log(`  - ${a.agent}: ${a.model}: ${gw.skip}`); continue; }
    if (!groups.has(gw.base)) groups.set(gw.base, { gw, agents: [] });
    groups.get(gw.base).agents.push(a);
  }
  if (!groups.size) { console.log("  - skipped: no agent model maps to a provider in Pi's models.json, and FACTORY_GATEWAY_URL is empty"); process.exit(0); }

  for (const { gw, agents: group } of groups.values()) {
    console.log(`  ${gw.name}: ${gw.base}`);
    if (!gw.key) warn(`${gw.name}: no key resolved: requests go out unauthenticated`);
    // 1. The gateway serves every configured model.
    const list = await call(gw, "/models").catch((e) => ({ status: 0, text: String(e.message || e) }));
    if (list.status !== 200) {
      bad(`${gw.name}: GET ${gw.base}/models → ${list.status || "no answer"} ${(list.text || "").slice(0, 300)}${list.status === 404 && !/\/v\d+$/.test(gw.base) ? " (does baseUrl need /v1?)" : ""}`);
      continue;
    }
    let served = [];
    try { served = JSON.parse(list.text).data.map((m) => m.id); } catch { warn(`${gw.name}: GET /models answered without a model list; skipping the served check`); }
    let missing = false;
    for (const a of group) {
      if (served.length && !served.includes(bareId(a.model))) { bad(`${a.agent}: ${a.model} is not served to this key on ${gw.name} (offers: ${served.join(", ")})`); missing = true; }
      else ok(`${a.agent}: ${a.model} served`);
    }
    if (missing) continue;

    // 2. Each (model, thinking) survives a tool turn; read its quota.
    const quotaSeen = new Set();
    const pairs = [...new Map(group.map((a) => [`${a.model}@${a.thinking}`, a])).values()];
    for (const a of pairs) {
      const r = await call(gw, "/chat/completions", toolTurn(bareId(a.model), a.thinking)).catch((e) => ({ status: 0, text: String(e.message || e), short: String(e.message || e), headers: new Headers() }));
      const who = `${bareId(a.model)} (thinking ${a.thinking})`;
      if (r.status === 200) {
        const q = quota(r.headers);
        ok(`${who}: tool turn accepted${q.req || q.tok ? `, quota ${q.req || "?"} req / ${q.tok || "?"} tokens per window` : ""}`);
        if (quotaSeen.has(a.model)) continue;
        quotaSeen.add(a.model);
        if (q.req && q.req < 30) warn(`${who}: ${q.req} requests per window is too low for a worker (dozens of calls per ticket); use FACTORY_MAX_PARALLEL=1 or ask for more`);
        if (q.tok && q.tok < 100000) warn(`${who}: ${q.tok} tokens per window; a worker resends its whole context every turn, expect 429 pauses`);
      } else if (r.status === 429) {
        warn(`${who}: 429 during the probe, quota exhausted right now; probe again later`); failed = true;
      } else if (r.status === 401 || r.status === 403) {
        bad(`${who}: ${r.status}, this key may not use this model on ${gw.name}: ${r.short}`);
      } else if (/reasoning/i.test(r.text)) {
        bad(`${who}: thinking level refused (${r.status}): set "thinking: off" or another level for agents on this model`);
      } else if (/role|order/i.test(r.text)) {
        bad(`${who}: rejects a user turn after a tool result (${r.status}): unusable for multi-turn agents (worker, reviewers); keep it for single-pass roles or the lead`);
      } else {
        bad(`${who}: ${r.status || "no answer"} ${r.short}`);
      }
    }
  }

  if (!failed && process.argv.includes("--stamp")) { writeFileSync(STAMP, modelsHash(agents) + "\n"); ok(`stamped ${STAMP}`); }
  console.log(failed ? "PROBE: FAIL" : "PROBE: OK");
  process.exit(failed ? 1 : 0);
}

if (process.argv[1] && process.argv[1].endsWith("models-probe.mjs")) {
  if (process.argv.includes("--hash")) { console.log(modelsHash()); process.exit(0); }
  if (process.argv.includes("--resolvable")) process.exit(agentModels().some((a) => !gatewayOf(a.model).skip) ? 0 : 1);
  main();
}
