// The scripted lead's "model" (D91): a Pi extension that registers a provider
// whose answers are code, not a language model. Its first answer is the one
// call the lead is allowed to make (D71):
//   subagent({ workflow: <FACTORY_DRIVE_WORKFLOW>, context: "fresh", async: false })
// its second ends the turn. No network, no tokens, nothing to improvise.
// run.sh loads it with:  pi -p --mode json -e scripts/factory/driver.mjs --model factory-driver/script
import { createFauxCore, fauxAssistantMessage, fauxText, fauxToolCall } from "@earendil-works/pi-ai";

export default function factoryDriver(pi) {
  const workflow = process.env.FACTORY_DRIVE_WORKFLOW;
  if (!workflow) return;
  const model = { id: "script", name: "factory script", reasoning: false, input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 128000, maxTokens: 4096 };
  const core = createFauxCore({ provider: "factory-driver", api: "factory-driver", models: [model] });
  const answer = (context) => {
    const called = (context.messages || []).some((m) => m.role === "toolResult");
    return called
      ? fauxAssistantMessage(fauxText("workflow returned"))
      : fauxAssistantMessage(fauxToolCall("subagent", { workflow, context: "fresh", async: false }), { stopReason: "toolUse" });
  };
  core.setResponses(Array.from({ length: 8 }, () => answer));
  pi.registerProvider("factory-driver", {
    api: core.api, streamSimple: core.streamSimple, baseUrl: "http://127.0.0.1:9", apiKey: "none", models: [model],
  });
}
