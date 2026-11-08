#!/usr/bin/env node
// Turns a real cockpit snapshot (status.sh --all --json) into a fixture the
// public repository can keep: structure, times, roles, rounds, results,
// costs and the guard's verdicts stay; everything a person or a model wrote
// goes, and so do model and gateway names, paths and the private causes.
//
// Usage: node scripts/dev/cockpit-fixture.mjs <state.json> > tests/fixtures/cockpit-gym.json
import { readFileSync } from "node:fs";

const s = JSON.parse(readFileSync(process.argv[2], "utf8"));
const models = new Map();
const model = (m) => (m ? (models.has(m) || models.set(m, `model-${String.fromCharCode(97 + models.size)}`), models.get(m)) : "");
const TEXT = "[text]";
const verdict = (v) => v && { result: v.result, round: v.round, commit: "", brief: "", model: model(v.model), blocking: v.blocking ? TEXT : "", file: v.file };

const missions = s.missions.map((m) => ({
  name: m.name, title: m.title, intent: m.intent, step: m.step, next: m.next ? TEXT : "", human: m.human, otherBranch: m.otherBranch ? "other" : "",
  paused: m.paused, question: m.question ? TEXT : "", mr: m.mr ? "closed" : "",
  contract: m.contract, counts: m.counts,
  tickets: m.tickets.map((t) => ({ ...t, assertions: [], journal: "", integrated: t.integrated ? "integrated" : "", verdict: verdict(t.verdict), history: (t.history || []).map(verdict) })),
  behavior: verdict(m.behavior), health: verdict(m.health), interventions: m.interventions,
  decisions: (m.decisions || []).map((d) => ({ date: d.date, ticket: d.ticket, kind: d.kind, question: TEXT, answer: TEXT, who: "" })),
  runs: [], usage: m.usage,
  log: (m.log || []).map((e) => ({ date: e.date, kind: e.kind, ticket: e.ticket, ok: e.ok, human: e.human, text: TEXT })),
  workers: [], needs: (m.needs || []).map((n) => ({ kind: n.kind, ticket: n.ticket, text: TEXT })),
  timeline: (m.timeline || []).map((r) => ({ ...r, model: model(r.model), refused: r.refused.map((g) => ({ at: g.at, rule: g.rule, tool: g.tool, input: TEXT, today: g.today })) })),
}));
process.stdout.write(JSON.stringify({ generated: s.generated, factoryDir: ".scratch", factory: s.factory, missions, bench: [], causes: [] }, null, 1) + "\n");
