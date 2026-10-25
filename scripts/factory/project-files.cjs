#!/usr/bin/env node
// Files the factory writes into a project and then leaves to it: the GitLab CI
// include and the subagents block of .pi/settings.json. Shared by
// install-into.sh (factory copied in) and onboard.sh (factory installed once
// per machine, P11, D92: --package).
//
// Usage: node project-files.cjs ci <template> <out> <prefix> <mr|child> [--package]
//        node project-files.cjs settings <template> <dst> <prefix> [--package]
const fs = require("fs");
const args = process.argv.slice(2).filter((a) => a !== "--package");
const pkg = process.argv.includes("--package");
const cmd = args[0];

if (cmd === "ci") {
  const [, from, to, prefix, mode] = args;
  let y = fs.readFileSync(from, "utf8");
  if (pkg) {
    // D92: the factory is not in the repository. Each job that runs a factory
    // script first fetches it and links it: from FACTORY_PACKAGE_GIT (a CI
    // variable, no default: the project decides where its CI may fetch from),
    // at the commit onboard recorded in .factory/package-sha, checked before
    // anything from it runs; into a directory of its own.
    const fetch = "    - 'test -e scripts/factory || { if [ -z \"$FACTORY_PACKAGE_GIT\" ]; then echo \"FACTORY_PACKAGE_GIT is not set (a CI variable, the URL of your pi-factory mirror)\" >&2; exit 1; fi; [ -s .factory/package-sha ] || { echo \".factory/package-sha missing (factory onboard records it)\" >&2; exit 1; }; sha=\"$(cat .factory/package-sha)\"; d=\"$(mktemp -d)\"; p=\"$(cat .factory/package-dir 2>/dev/null || true)\"; case \"$p\" in *..*|/*) echo \".factory/package-dir must be a folder inside the factory repository\" >&2; exit 1 ;; esac; git clone -q \"$FACTORY_PACKAGE_GIT\" \"$d/pi-factory\" && git -C \"$d/pi-factory\" checkout -q --detach \"$sha\" && [ \"$(git -C \"$d/pi-factory\" rev-parse HEAD)\" = \"$sha\" ] && bash \"$d/pi-factory/${p:+$p/}scripts/factory/link.sh\"; }'\n";
    y = y.replace(/^  script:\n(?=(?:    - .*\n)*?    - .*scripts\/factory\/)/gm, "  script:\n" + fetch)
         .replace("command -v bash >/dev/null && command -v node >/dev/null || apk add --no-cache bash nodejs", "command -v bash >/dev/null && command -v node >/dev/null && command -v git >/dev/null || apk add --no-cache bash nodejs git")
         .replace(/command -v bash >\/dev\/null \|\| apk add --no-cache bash$/m, "command -v bash >/dev/null && command -v git >/dev/null || apk add --no-cache bash git")
         .replace("node scripts/factory/models-lint.mjs", "node scripts/factory/models-lint.mjs --per-machine-ok")
         .replace(/^variables:\n/m, "# FACTORY_PACKAGE_GIT: set it as a CI/CD variable, the URL of your pi-factory mirror\n# (no default). Jobs check out the commit in .factory/package-sha.\nvariables:\n");
    const fetched = (y.match(/pi-factory\/\$\{p:\+\$p\/\}scripts\/factory\/link\.sh/g) || []).length;
    if (fetched !== 3) { console.error(`CI template: ${fetched}/3 jobs fetch the package; update project-files.cjs`); process.exit(1); }
  }
  const MR = /^(\s*)- if: \$CI_PIPELINE_SOURCE == "merge_request_event"$/gm;
  if (mode === "child") {
    // D57: started by the parent's trigger job, which passes the MR's target
    // and labels down; the parent already decides when this project changed.
    const n = (y.match(MR) || []).length;
    y = y.replace(MR, '$1- if: $CI_PIPELINE_SOURCE == "parent_pipeline" && $FACTORY_MR_TARGET');
    if (!n || (y.match(/parent_pipeline/g) || []).length !== n) { console.error("CI template: child rules not rewritten; update install-into.sh"); process.exit(1); }
  }
  if (prefix) {
    const slug = prefix.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");   // full path: two "bot" folders can't collide
    const q = JSON.stringify(prefix);
    const jobs = (y.match(/^[a-z][\w-]*:$/gm) || []).filter((k) => k !== "variables:").length;
    y = y.replace(/^(factory-gate|factory-config|behavior-replay|factory-readiness):$/gm, `$1-${slug}:`)
         .replace(MR, `$1- if: $CI_PIPELINE_SOURCE == "merge_request_event"\n$1  changes: [${JSON.stringify(prefix + "/**/*")}]`)
         .replace(/^  script:\n/gm, `  script:\n    - cd ${q}\n`);
    const renamed = (y.match(new RegExp(`^[a-z-]+-${slug}:$`, "gm")) || []).length;
    const scoped = (y.match(/^\s+changes: \[/gm) || []).length + (y.match(/parent_pipeline/g) || []).length;
    if (renamed !== jobs || scoped !== jobs) { console.error(`CI template: ${renamed}/${jobs} jobs renamed, ${scoped} scoped; update install-into.sh`); process.exit(1); }
    y = `# Monorepo project: ${prefix}. Include from your CI with:\n#   include: [{ local: ${JSON.stringify(prefix + "/.factory/ci/factory.gitlab-ci.yml")} }]\n` + y;
  }
  if (mode === "child") {
    y = `# Child pipeline (D57). The parent's trigger job must pass the MR down and wait for the result:\n#   variables: { FACTORY_MR_TARGET: $CI_MERGE_REQUEST_TARGET_BRANCH_NAME, FACTORY_MR_LABELS: $CI_MERGE_REQUEST_LABELS }\n#   trigger: { include: <this project's CI file>, strategy: depend }\n` + y;
  }
  fs.writeFileSync(to, y);
} else if (cmd === "settings") {
  const [, srcFile, dstFile, prefix] = args;
  const tpl = JSON.parse(fs.readFileSync(srcFile, "utf8"));
  const cur = fs.existsSync(dstFile) ? JSON.parse(fs.readFileSync(dstFile, "utf8")) : {};
  const had = !!cur.subagents;
  const { agentOverrides: _ignored, ...tplSub } = tpl.subagents;          // models live in agent frontmatter (D31)
  cur.subagents = { ...tplSub, ...(cur.subagents || {}) };
  // D92: on the package, the model scope is per machine (models-profile apply
  // --user); a placeholder scope here would override it and block every model.
  const ms = cur.subagents.modelScope;
  if (pkg && ms && (ms.allow || []).some((a) => /[<>]/.test(a))) delete cur.subagents.modelScope;
  // Retries on rate limits (mission 1: a shared quota of about 10 requests per
  // window); yours win if already set.
  if (tpl.retry && !cur.retry) cur.retry = tpl.retry;
  // In a monorepo the project is this folder, not the git root (D56).
  if (prefix) cur.subagents.projectRootResolution = "nearest";
  const ov = cur.subagents.agentOverrides || {};
  // Kept: pi-subagents 0.76.1 applies agentOverrides to factory-* agents (D92 spike).
  if (cur.subagents.agentOverrides && !Object.keys(ov).length) delete cur.subagents.agentOverrides;
  fs.mkdirSync(require("path").dirname(dstFile), { recursive: true });
  fs.writeFileSync(dstFile, JSON.stringify(cur, null, 2) + "\n");
  console.log(`  .pi/settings.json: ${had ? "merged (your existing subagents values kept)" : "factory subagents block added"}${cur.retry ? ", retry on rate limits" : ""}`);
} else {
  console.error("usage: project-files.cjs ci|settings ...");
  process.exit(2);
}
