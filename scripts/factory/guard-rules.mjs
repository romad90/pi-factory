// Command guard rules (D51). Pure functions, no I/O except existsSync, so
// they are unit-tested (tests/guard.test.mjs) and shared by the Pi extension
// .pi/extensions/factory-guard.ts, which blocks matching tool calls live.
//
// The guard is the first barrier, not the only one: whatever slips through,
// scripts/factory/patch-guard.sh rejects at integration, and CI gates the MR.
//
// check({ tool, input, cwd, home }) → null | { rule, reason }
import { existsSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";

// Bash commands that are never an agent's to run. Each: [rule, regex, reason].
const BASH_RULES = [
  // Destruction outside the worktree, or of the repo itself
  ["destroy", /\brm\s+(-[a-zA-Z]*[rR][a-zA-Z]*\s+|--recursive\s+)(-[a-zA-Z]+\s+)*(\/|~|\$HOME|\.\.|\*|\.git\b|\/\*)(\s|$|\/)/, "recursive delete of /, ~, .., * or .git"],
  ["destroy", /\b(mkfs|shred|wipefs)\b|\bdd\s+.*\bof=\/dev\//, "disk-level destructive command"],
  ["destroy", /:\(\)\s*\{\s*:\|:&\s*\};:/, "fork bomb"],
  ["destroy", /\bfind\b.*\s-delete\b.*(^|\s)(\/|~)(\s|$)|\bfind\s+(\/|~)\s.*-delete\b/, "find -delete from / or ~"],
  // Privilege
  ["privilege", /(^|[;&|]\s*|\s)(sudo|doas|su)\s/, "privilege escalation"],
  ["privilege", /\bchmod\s+(-R\s+)?[0-7]*777\b|\bchown\s+-R\b/, "permission change on a tree"],
  // Git: history and remotes belong to the human and CI
  ["git", /\bgit\s+push\b/, "git push (the human pushes; CI gates)"],
  ["git", /--no-verify\b/, "skipping hooks (--no-verify)"],
  ["git", /\bgit\s+(filter-branch|filter-repo|update-ref\s+-d|reflog\s+expire|gc\s+--prune)/, "rewriting or pruning git history"],
  ["git", /\bgit\s+config\s+--(global|system)\b/, "changing global git config"],
  ["git", /\bgit\s+remote\s+(add|set-url|remove|rm)\b/, "changing git remotes"],
  // Production and shared infrastructure
  ["infra", /\b(kubectl|oc)\s+(apply|create|delete|edit|patch|replace|scale|rollout|drain|cordon|exec|port-forward)\b/, "cluster change"],
  ["infra", /\bhelm\s+(install|upgrade|uninstall|delete|rollback)\b/, "helm release change (helm lint/template are fine)"],
  ["infra", /\bterraform\s+(apply|destroy|import|state)\b|\bpulumi\s+(up|destroy)\b/, "infrastructure change"],
  ["infra", /\b(aws|gcloud|az)\s+\S+/, "cloud CLI"],
  ["infra", /\bvault\s+(write|delete|kv\s+(put|delete|destroy))\b/, "secret store change"],
  ["infra", /\bdocker\s+(push|login)\b|\bdocker\s+run\b.*--privileged/, "registry push or privileged container"],
  // Leaving the machine
  ["egress", /\b(curl|wget)\b[^|]*\|\s*(ba|z|da)?sh\b/, "piping a download into a shell"],
  ["egress", /\bcurl\b.*(\s-d\s*@|--data(-binary|-raw)?\s+@|\s-T\s|--upload-file|\s-F\s+\S*=@)/, "uploading a file with curl"],
  ["egress", /\b(scp|sftp|rsync\s+\S*\s+\S*:|nc|ncat|netcat|socat|telnet|ssh)\s/, "remote copy or shell"],
  ["egress", /\/dev\/(tcp|udp)\//, "raw network socket"],
  // Secrets on the machine
  ["secrets", /(~|\$HOME|\/home\/[^/\s]+|\/Users\/[^/\s]+)\/\.(ssh|aws|gnupg|kube|docker|netrc|npmrc|pypirc|config\/gcloud)/, "reading credentials from the home folder"],
  ["secrets", /(^|[\s"'=:])\/(var\/)?run\/secrets(\/|\s|$)/, "reading secrets mounted into a container (Kubernetes service account token)"],
  ["secrets", /\.pi\/agent\/(models|auth)\.json\b/, "reading Pi's provider keys"],
  ["secrets", /(^|[;&|]\s*)(printenv|env)\s*($|[;&|>])|\/proc\/\S*\/environ|\bsecurity\s+find-(generic|internet)-password\b/, "dumping environment or keychain secrets"],
  ["secrets", /\b(cat|less|more|head|tail|source|\.)(\s[^|;&]*)?[\s/]\.env(\.(?!example\b|sample\b|template\b|factory\b)[a-z]+)?(\s|$)/, "reading a .env file"],
  // Publishing and merging
  ["publish", /\b(npm|pnpm|yarn)\s+publish\b|\btwine\s+upload\b|\bcargo\s+publish\b|\bgem\s+push\b/, "publishing a package"],
  ["publish", /\b(gh|glab)\s+(pr|mr)\s+merge\b|\bgh\s+release\s+create\b|\bglab\s+release\s+create\b/, "merging or releasing"],
  // The guard itself
  ["guard", /FACTORY_GUARD\s*=/, "changing the guard"],
  // Context repos (D99): read them, never act in them. The clones are also
  // read-only on disk; this catches git and redirections before they try.
  ["context", /\bgit\s+(-C\s+|--git-dir[=\s]+|--work-tree[=\s]+)["']?[^\s"']*\.factory\/context\b/, "git in a context repo (read them with read/grep; they change through their own team)"],
  ["context", /\bcd\s+["']?[^\s"';&|]*\.factory\/context\b[^;&|]*(&&|;|\|\|)\s*git\b/, "git in a context repo (read them with read/grep; they change through their own team)"],
  ["context", />>?\s*["']?[^\s"']*\.factory\/context\//, "writing into a context repo"],
  // Mission records: scripts write them, nobody deletes them (D71)
  ["records", /\brm\b[^;&|]*\.scratch\//, "deleting mission files in .scratch/ (they are the record; the scripts change them)"],
];

// D100: a worker's hands stay off the network. Dependencies are linked into
// its worktree (D65), so it never needs to download, install or reach a
// remote; anything leaving the machine from there is either a mistake or an
// injected instruction. The lead and the human are not concerned.
const WORKER_BASH_RULES = [
  ["network", /(^|[;&|(]\s*|\s)(curl|wget|httpie|http|xh|aria2c)\s/, "network access from a worker (its dependencies are already linked)"],
  ["network", /\b(npm|pnpm|yarn|bun)\s+(i|install|add|ci|update|upgrade|up|dlx)\b|\bnpx\s+(-y|--yes|-p|--package)\b|\bnpm\s+exec\s+(-y|--yes)\b/, "installing or fetching packages from a worker"],
  ["network", /\b(pip3?|uv\s+pip|poetry|pipx)\s+(install|add)\b|\bpython3?\s+-m\s+pip\s+install\b|\buv\s+(add|sync)\b/, "installing Python packages from a worker"],
  ["network", /\b(cargo|go|gem)\s+(install|get|fetch)\b|\bgo\s+mod\s+download\b/, "fetching packages from a worker"],
  ["network", /\bgit\s+(fetch|clone|pull|ls-remote|submodule\s+update)\b/, "reaching a git remote from a worker"],
  ["network", /\b(python3?|node|ruby|perl)\b[^|;&]*\b(urllib|requests\.|http\.client|socket\.|fetch\(|https?:\/\/|Net::HTTP|LWP)/, "network access through an interpreter from a worker"],
  // D100: the linked dependency folders belong to the main checkout.
  ["deps", /(>>?|\btee\b|\bsed\s+-i|\b(cp|mv|rm|ln|chmod|chown|touch|patch|install|truncate)\b)[^;&|]*(^|[\s/"'])(node_modules|\.venv)\//, "changing the shared dependency folder (it is the main checkout's, linked into the worker)"],
];
const WORKER_WRITE_DEPS = /(^|\/)(node_modules|\.venv)\//;

// A factory worker: a git worktree whose branch pi-subagents created
// (pi-subagents/<ticket>-...). Read from the worktree's .git file and HEAD.
function isWorker(cwd) {
  if (process.env.FACTORY_ROLE === "worker") return true;
  for (let d = resolve(cwd); ; d = dirname(d)) {
    const g = join(d, ".git");
    if (existsSync(g)) {
      try {
        if (!statSync(g).isFile()) return false;
        const m = readFileSync(g, "utf8").match(/^gitdir:\s*(.+)$/m);
        if (!m) return false;
        const gitdir = isAbsolute(m[1].trim()) ? m[1].trim() : resolve(d, m[1].trim());
        return /^ref:\s*refs\/heads\/pi-subagents\//.test(readFileSync(join(gitdir, "HEAD"), "utf8"));
      } catch { return false; }
    }
    if (dirname(d) === d) return false;
  }
}

// D100: the hands hold no secrets. Every bash call in a factory project runs
// with credential-like variables unset, so an injected "print your env" or a
// test that logs process.env finds nothing. The harness keeps its own copy to
// call the model. Names: the gateway key variable, the env vars Pi's
// models.json names as apiKey, and *_TOKEN, *_KEY, *_SECRET, *PASSWORD*;
// FACTORY_TOOL_ENV_KEEP (space-separated) lets a project keep one it needs.
const SECRET_NAME = /(_TOKEN|_KEY|_SECRET|_SECRETS|_APIKEY|_API_KEY|_PAT|_CREDENTIALS?)$|PASSWORD|PASSWD|^(GITLAB|GITHUB|GH|GL|NPM|AWS|AZURE|GOOGLE|OPENAI|ANTHROPIC|OPENROUTER)_(TOKEN|KEY)/i;
export function secretEnvNames({ env = process.env, modelsJson = null } = {}) {
  const keep = new Set(String(env.FACTORY_TOOL_ENV_KEEP ?? "").split(/\s+/).filter(Boolean));
  const names = new Set();
  if (env.FACTORY_GATEWAY_KEY_ENV) names.add(env.FACTORY_GATEWAY_KEY_ENV);
  try {
    const providers = (modelsJson ?? {}).providers ?? {};
    for (const p of Object.values(providers)) {
      const k = p && typeof p.apiKey === "string" ? p.apiKey.replace(/^\$\{?|\}$/g, "") : "";
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && k in env) names.add(k);
    }
  } catch { /* models.json unreadable: the name rules still apply */ }
  for (const n of Object.keys(env)) if (SECRET_NAME.test(n)) names.add(n);
  for (const n of keep) names.delete(n);
  return [...names].filter((n) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(n)).sort();
}
// The command, with those variables unset first in the same shell.
export function scrubCommand(command, names) {
  if (!names.length) return command;
  return `unset ${names.join(" ")} 2>/dev/null\n${command}`;
}
export function inFactoryProject(cwd) {
  for (let d = resolve(cwd); ; d = dirname(d)) {
    if (existsSync(join(d, ".factory"))) return true;
    if (dirname(d) === d) return false;
  }
}

// D71: in a factory project, agents start only from a workflow file that
// workflow.sh generated: subagent({ workflow: "<WORKFLOW_FILE>", ... }). A
// direct call (agent, tasks, chain, an inline script) is the lead improvising.
const WORKFLOW_FILE = /(^|\/)\.scratch\/.+\.js$/;
const SUBAGENT_ALLOWED = new Set(["workflow", "context", "async", "action", "id", "runId"]);
// D75: the one direct call a factory agent needs: a reviewer dispatching a
// code-review axis to the read-only factory-review-axis agent, fresh.
const AXIS_ALLOWED = new Set(["agent", "task", "context", "async"]);
const isAxisDispatch = (i) => i.agent === "factory-review-axis" && typeof i.task === "string"
  && (i.context === undefined || i.context === "fresh") && Object.keys(i).every((k) => AXIS_ALLOWED.has(k));

// Paths no agent writes or edits.
const PROTECTED_WRITE = /^(\.git\/|\.factory\/|scripts\/factory\/|\.pi\/|\.github\/|\.gitlab-ci\.yml$|\.husky\/|\.pre-commit-config\.yaml$|lefthook\.yml$)/;
// Paths no agent reads.
const SECRET_READ = /(^|\/)\.pi\/agent\/(models|auth)\.json$|^\/(var\/)?run\/secrets(\/|$)|(^|\/)\.(ssh|aws|gnupg|kube|netrc|npmrc|pypirc)(\/|$)|(^|\/)\.env(\.[a-z]+)?$|(^|\/)id_(rsa|ed25519|ecdsa)(\.pub)?$/;
const SECRET_READ_OK = /(^|\/)\.env\.(example|sample|template|factory)$/;

const TEMP_DIRS = [...new Set([tmpdir(), "/tmp", "/var/tmp"].map((d) => d.replace(/\/+$/, "")))];
const isTemp = (abs) => TEMP_DIRS.some((d) => abs === d || abs.startsWith(d + "/"));

function rel(p, cwd, root = cwd) {      // resolve from the agent's cwd, report from the project root
  const abs = isAbsolute(p) ? p : resolve(cwd, p);
  return abs.startsWith(root + "/") ? abs.slice(root.length + 1) : abs;
}

// The factory project the agent works in: the nearest folder with .factory/
// (a repo root, or a folder of a monorepo, D56); else a plain git repo root.
function projectRoot(cwd) {
  for (let d = resolve(cwd); ; d = dirname(d)) {
    if (existsSync(join(d, ".factory"))) return d;
    if (dirname(d) === d) break;
  }
  return existsSync(join(cwd, ".git")) ? cwd : null;
}

// A worker's worktree has no instrument/ (sparse checkout, D35). From there,
// any route to it (git show, git log -p, another checkout) breaks the wall.
function hidesInstrument(cwd) {
  const root = projectRoot(cwd);
  return !!root && !existsSync(join(root, "instrument"));
}

export function check({ tool, input = {}, cwd = process.cwd() }) {
  if (process.env.FACTORY_GUARD === "off") return null;
  if (tool === "subagent") {
    if (input.action !== undefined || !projectRoot(cwd)) return null;   // status, list: harmless
    const extra = Object.keys(input).filter((k) => !SUBAGENT_ALLOWED.has(k));
    if (typeof input.workflow === "string" && WORKFLOW_FILE.test(input.workflow) && !extra.length) return null;
    if (isAxisDispatch(input)) return null;
    return { rule: "lead", reason: `factory agents start only from a generated workflow file: subagent({ workflow: "<the WORKFLOW_FILE path workflow.sh printed>", context: "fresh", async: false })${extra.length ? `, without ${extra.join(", ")}` : ""}: blocked by the factory guard` };
  }
  if (tool === "bash") {
    const cmd = String(input.command ?? "");
    for (const [rule, re, reason] of BASH_RULES) {
      if (re.test(cmd)) return { rule, reason: `${reason}: blocked by the factory guard` };
    }
    if (isWorker(cwd)) {
      for (const [rule, re, reason] of WORKER_BASH_RULES) {
        if (re.test(cmd)) return { rule, reason: `${reason}: blocked by the factory guard` };
      }
    }
    if (hidesInstrument(cwd) && /\binstrument\//.test(cmd)) {
      return { rule: "wall", reason: "the instrument is hidden from workers (D21): blocked by the factory guard" };
    }
    return null;
  }
  const path = input.path ?? input.file_path ?? input.filePath;
  if (!path) return null;
  const r = rel(String(path), resolve(cwd), projectRoot(cwd) ?? resolve(cwd));
  if ((tool === "write" || tool === "edit") && /^\.factory\/context\//.test(r)) {
    return { rule: "context", reason: `${r} is in a context repo: read-only, it changes through its own team (D99): blocked by the factory guard` };
  }
  if ((tool === "write" || tool === "edit") && isWorker(cwd) && WORKER_WRITE_DEPS.test(r)) {
    return { rule: "deps", reason: `${r} is in the shared dependency folder (the main checkout's, linked into the worker): blocked by the factory guard` };
  }
  if ((tool === "write" || tool === "edit") && PROTECTED_WRITE.test(r)) {
    return { rule: "paths", reason: `${r} belongs to the factory, CI or hooks: blocked by the factory guard` };
  }
  // D99: a mission changes one project. Inside a factory project, nothing is
  // written outside it (a sibling repo, a sibling project of a monorepo, $HOME).
  // The temp folder stays writable: scratch files (a PR body, a plan) are not a change.
  if ((tool === "write" || tool === "edit") && isAbsolute(r) && projectRoot(cwd) && !isTemp(r)) {
    return { rule: "outside", reason: `${r} is outside the project ${projectRoot(cwd)}: a mission changes one repo (D99): blocked by the factory guard` };
  }
  if (SECRET_READ.test(r) && !SECRET_READ_OK.test(r)) {
    return { rule: "secrets", reason: `${r} holds credentials: blocked by the factory guard` };
  }
  if (hidesInstrument(cwd) && /^instrument\//.test(r)) {
    return { rule: "wall", reason: "the instrument is hidden from workers (D21): blocked by the factory guard" };
  }
  return null;
}
