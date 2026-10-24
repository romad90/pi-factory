// Command guard rules (D51). Pure functions, no I/O except existsSync, so
// they are unit-tested (tests/guard.test.mjs) and shared by the Pi extension
// .pi/extensions/factory-guard.ts, which blocks matching tool calls live.
//
// The guard is the first barrier, not the only one: whatever slips through,
// scripts/factory/patch-guard.sh rejects at integration, and CI gates the MR.
//
// check({ tool, input, cwd, home }) → null | { rule, reason }
//
// D101: rules are tested against the command as written, against it
// normalized (quotes and backslashes inside words removed, ${IFS} and
// newlines turned into separators: c''url, "curl" and \curl are curl), and
// against it with git's global options removed (git -c k=v --no-pager push is
// git push). It is a rule-level defence: a command built at run time (a
// variable, base64, a script file) is not seen; what holds without it is the
// scrubbed environment, the push-less remotes and patch-guard at integration.
import { existsSync, readFileSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";

// Command position: start, or after ; & | ( ` $( , then any wrappers.
const CMDPOS = String.raw`(?:^|[;&|(\x60]|\$\()\s*(?:(?:sudo|nohup|exec|time|command|builtin|nice(?:\s+-n\s*\S+)?|timeout\s+\S+|xargs(?:\s+-\S+)*|env(?:\s+-\S+)*|\w+=\S*|(?:ba|z|da|k)?sh\s+-c)\s+)*`;
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
  ["git", /\bgit\s+(-c\s+)?alias\.|\bgit\s+config\b[^;&|]*\balias\./, "defining a git alias (it can hide any command)"],
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
  ["secrets", /\.pi\/agent\b|(~|\$HOME|\$\{HOME\})\/\.pi(\/|\s|$)|\$\{?PI_CODING_AGENT_DIR\b|\bagent\/(models|auth)\.json\b/, "reaching Pi's agent folder (its auth.json and models.json hold the provider keys)"],
  ["secrets", /(^|[;&|(]\s*)(printenv|env)\s*($|[;&|>)])|\/environ\b|\bproc\/(\d+|self|thread-self)\/|\bsecurity\s+find-(generic|internet)-password\b/, "dumping environment or keychain secrets"],
  ["secrets", new RegExp(`${CMDPOS}(?:\\S*\\/)?ps\\b[^;&|)]*\\s(?:[a-zA-Z]*e[a-zA-Z]*|-[a-zA-Z]*E[a-zA-Z]*)(?=\\s|$|[;&|)])`), "ps with environments (e, -E): other processes' secrets"],
  ["secrets", /\b(cat|less|more|head|tail|source|\.)(\s[^|;&]*)?[\s/]\.env(\.(?!example\b|sample\b|template\b|factory\b)[a-z]+)?(\s|$)/, "reading a .env file"],
  // Publishing and merging
  ["publish", /\b(npm|pnpm|yarn)\s+publish\b|\btwine\s+upload\b|\bcargo\s+publish\b|\bgem\s+push\b/, "publishing a package"],
  ["publish", /\b(gh|glab)\s+(pr|mr)\s+merge\b|\bgh\s+release\s+create\b|\bglab\s+release\s+create\b/, "merging or releasing"],
  // The guard itself
  ["guard", /FACTORY_GUARD\s*=/, "changing the guard"],
  // Context repos (D99): read them, never act in them. git there is analysed
  // below (gitCalls): only read-only subcommands pass.
  ["context", /(>>?|\btee\b|\bsed\s+[^;&|]*-i|\b(cp|mv|install|ln|chmod|chown|rm|touch|truncate|patch|rsync)\b)[^;&|]*\.factory\/context\b/, "changing a context repo (read-only: it changes through its own team)"],
  ["context", /\bcontext\.sh\b[^;&|]*\brelease\b/, "giving a context repo write permission back (the human's step)"],
  // The factory's own folder (D101): agents change it with no tool, bash included.
  ["paths", />>?\s*[^\s;&|]*\.factory(\/|\s|$)|\btee\b[^;&|]*\.factory(\/|\s|$)|\bsed\s+[^;&|]*-i[^;&|]*\.factory(\/|\s|$)|\b(cp|mv|install|ln|rsync)\b[^;&|]*\s[^\s;&|]*\.factory(\/[^\s;&|]*)?\s*($|[;&|)])|\b(chmod|chown|rm|touch|truncate)\b[^;&|]*\.factory(\/|\s|$)|\bdd\b[^;&|]*\bof=[^\s;&|]*\.factory\//, "writing into .factory/ (the factory's configuration and context repos)"],
  // Approvals are the human's (D101): a line counts only with its decisions.tsv
  // row from human.sh, and no agent writes either by hand.
  ["approval", /(>>?|\btee\b|\bsed\s+[^;&|]*-i|\b(cp|mv|install|ln|truncate|rm)\b)[^;&|]*decisions\.tsv\b/, "writing decisions.tsv by hand (human.sh logs decisions)"],
  // Mission records: scripts write them, nobody deletes them (D71)
  ["records", /\brm\b[^;&|]*\.scratch\//, "deleting mission files in .scratch/ (they are the record; the scripts change them)"],
];

// D100: a worker's hands stay off the network. Dependencies are linked into
// its worktree (D65), so it never needs to download, install or reach a
// remote; anything leaving the machine from there is either a mistake or an
// injected instruction. The lead and the human are not concerned.
const WORKER_BASH_RULES = [
  // In command position only (D101): grep -rn http src and --url http://… pass.
  ["network", new RegExp(`${CMDPOS}(?:\\S*\\/)?(curl|wget|httpie|http|https|xh|aria2c|lynx|w3m|links)(?=\\s|$|[;&|)])`), "network access from a worker (its dependencies are already linked)"],
  ["network", /\b(npm|pnpm|yarn|bun)\s+(i|install|add|ci|update|upgrade|up|dlx)\b|\bnpx\s+(-y|--yes|-p|--package)\b|\bnpm\s+exec\s+(-y|--yes)\b/, "installing or fetching packages from a worker"],
  ["network", /\b(pip3?|uv\s+pip|poetry|pipx)\s+(install|add)\b|\bpython3?\s+-m\s+pip\s+install\b|\buv\s+(add|sync)\b/, "installing Python packages from a worker"],
  ["network", /\b(cargo|go|gem)\s+(install|get|fetch)\b|\bgo\s+mod\s+download\b/, "fetching packages from a worker"],
  ["network", /\bgit\s+(fetch|clone|pull|ls-remote|submodule|remote\s+update|archive\s+--remote)\b/, "reaching a git remote from a worker"],
  // Inline code only (-c, -e, --eval, -p): a test runner given a URL passes.
  ["network", new RegExp(`${CMDPOS}(?:\\S*\\/)?(python[\\d.]*|node|nodejs|ruby|perl|php|deno|bun)\\s+(?:-\\S+\\s+)*?(?:-c|-e|-E|--eval|-p|--print|-r\\s*\\S*\\s+-e)\\s[^;&|]*?(urllib|requests|http\\.client|httpx|aiohttp|socket|fetch\\s*\\(|https?:\\/\\/|Net::HTTP|LWP|axios|undici|net\\.connect|XMLHttpRequest|WebSocket|curl_)`), "network access through an interpreter from a worker"],
  // A worker never answers for the human (D101).
  ["approval", /\bhuman\.sh\s+(approve|amend|decide|accept-unverified)\b/, "a worker running a human gate"],
  // D100: the linked dependency folders belong to the main checkout.
  ["deps", /(>>?|\btee\b|\bsed\s+-i|\b(cp|mv|rm|ln|chmod|chown|touch|patch|install|truncate)\b)[^;&|]*(^|[\s/"'])(node_modules|\.venv)\//, "changing the shared dependency folder (it is the main checkout's, linked into the worker)"],
];
const WORKER_WRITE_DEPS = /(^|\/)(node_modules|\.venv)\//;

// A factory worker: a git worktree whose branch pi-subagents created
// (pi-subagents/<ticket>-...). Read from the worktree's .git file and HEAD.
// D101: the benchmark's agents too: FACTORY_ROLE=worker (bench.sh sets it), or
// a worktree under the git common dir's pi-factory/bench/.
function isWorker(cwd) {
  if (process.env.FACTORY_ROLE === "worker") return true;
  if (/\/pi-factory\/bench\//.test(resolve(cwd) + "/")) return true;
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
// models.json names as apiKey, and *_TOKEN, *_KEY, *_SECRET, *PASSWORD*,
// *JWT*, *_AUTH*, *CREDENTIAL*, *COOKIE*, SSH_AUTH_SOCK, GIT_ASKPASS,
// SSH_ASKPASS (D101), and any variable whose value is a URL with credentials
// (scheme://user:pass@host). FACTORY_TOOL_ENV_KEEP (space-separated, from the
// harness's own environment only, never a project file) lets a project keep
// one it needs; it can never keep the gateway key or a models.json key.
// A rule-level defence: it removes what a command finds by name, it is not
// proof against an injection that already runs code with the harness's rights.
const SECRET_NAME = /(_TOKEN|_KEY|_SECRET|_SECRETS|_APIKEY|_API_KEY|_PAT|_CREDENTIALS?)$|PASSWORD|PASSWD|JWT|CREDENTIAL|COOKIE|(^|_)AUTH(_|$|ORIZATION)|^SSH_AUTH_SOCK$|^(GIT|SSH|SUDO)_ASKPASS$|^(GITLAB|GITHUB|GH|GL|NPM|AWS|AZURE|GOOGLE|OPENAI|ANTHROPIC|OPENROUTER)_(TOKEN|KEY)/i;
const CRED_URL = /^[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^@\s/]+@/i;
export function secretEnvNames({ env = process.env, modelsJson = null } = {}) {
  const keep = new Set(String(env.FACTORY_TOOL_ENV_KEEP ?? "").split(/\s+/).filter(Boolean));
  const names = new Set();
  const pinned = new Set();                 // never kept, whatever FACTORY_TOOL_ENV_KEEP says
  if (env.FACTORY_GATEWAY_KEY_ENV) pinned.add(env.FACTORY_GATEWAY_KEY_ENV);
  try {
    const providers = (modelsJson ?? {}).providers ?? {};
    for (const p of Object.values(providers)) {
      const k = p && typeof p.apiKey === "string" ? p.apiKey.replace(/^\$\{?|\}$/g, "") : "";
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(k) && k in env) pinned.add(k);
    }
  } catch { /* models.json unreadable: the name rules still apply */ }
  for (const [n, v] of Object.entries(env)) if (SECRET_NAME.test(n) || CRED_URL.test(String(v ?? ""))) names.add(n);
  for (const n of keep) names.delete(n);
  for (const n of pinned) names.add(n);
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
// Pi's agent folder (D101): ~/.pi/agent, or PI_CODING_AGENT_DIR when set.
export function agentDir(env = process.env) {
  return resolve(env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"));
}
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

// --- D101: what a command really says -----------------------------------------

// The command with quoting removed: c''url, "curl", \curl and c$''url are curl;
// ${IFS} is a space; line continuations join; newlines separate commands.
export function normalize(cmd) {
  return String(cmd ?? "")
    .replace(/\\\r?\n/g, " ")
    .replace(/\$(''|"")/g, "")
    .replace(/\$\{IFS\}|\$IFS\b/g, " ")
    .replace(/\\(.)/g, "$1")
    .replace(/["']/g, "")
    .replace(/\r?\n/g, " ; ")
    .replace(/[ \t]+/g, " ")
    .trim();
}

// Each git invocation: its subcommand, arguments and the folders it acts on
// (-C, --git-dir, --work-tree, GIT_DIR=, GIT_WORK_TREE=, or a cd before it in
// the same command), with git's global options skipped: git -c k=v --no-pager
// -C x push is a push.
const GIT_OPT_VALUE = new Set(["-c", "-C", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix", "--exec-path-value"]);
export function gitCalls(cmd) {
  const calls = [];
  let cdDir = null;
  for (const seg of normalize(cmd).split(/\s*(?:&&|\|\||[;&|()`]|\$\()\s*/)) {
    const t = seg.split(/\s+/).filter(Boolean);
    if (!t.length) continue;
    if (t[0] === "cd" || t[0] === "pushd") { cdDir = t[1] ?? "~"; continue; }
    const envDirs = [];
    for (let i = 0; i < t.length; i++) {
      const m = t[i].match(/^GIT_(?:DIR|WORK_TREE)=(.*)$/);
      if (m) { envDirs.push(m[1]); continue; }
      if (!(t[i] === "git" || t[i].endsWith("/git"))) continue;
      const call = { sub: "", args: [], dirs: [...(cdDir ? [cdDir] : []), ...envDirs], config: [] };
      let j = i + 1;
      for (; j < t.length; j++) {
        const a = t[j];
        if (!a.startsWith("-")) break;
        if (GIT_OPT_VALUE.has(a)) {
          const v = t[++j] ?? "";
          if (a === "-C" || a === "--git-dir" || a === "--work-tree") call.dirs.push(v);
          if (a === "-c" || a === "--config-env") call.config.push(v);
          continue;
        }
        const eq = a.match(/^--(git-dir|work-tree)=(.*)$/);
        if (eq) { call.dirs.push(eq[2]); continue; }
        // any other global flag (--no-pager, -P, --bare, --namespace=x, …)
      }
      call.sub = t[j] ?? "";
      call.args = t.slice(j + 1);
      calls.push(call);
      i = t.length;                          // one git per segment
    }
  }
  return calls;
}

// /proc: only what describes the machine (D101). Everything else there can
// hold another process's environment or memory.
const PROC_OK = new Set(["/proc/cpuinfo", "/proc/meminfo", "/proc/loadavg", "/proc/version", "/proc/stat"]);
function procPath(n) {
  for (const m of n.matchAll(/(^|[^\w])(\/proc(?:\/[^\s;&|)<>]*)?)/g)) {
    const p = m[2].replace(/\/+$/, "") || "/proc";
    if (!PROC_OK.has(p)) return p;
  }
  return null;
}

// Approval lines (D101): only human.sh writes them, with a decisions.tsv row.
const APPROVAL_WORDS = /\b(Contract|Design|Conclusion)\s+approved:(?!\**\s*pending\b)/i;
const APPROVAL_LINE = /^\*\*(Contract|Design|Conclusion) approved:\*\*[ \t]*(?!pending\b)\S.*$/gm;
const approvalLines = (t) => new Set((String(t ?? "").match(APPROVAL_LINE) || []).map((l) => l.trim()));
function newTexts(input) {                 // what a write or an edit puts in the file
  const out = [];
  const walk = (v, key = "") => {
    if (typeof v === "string") { if (/^(content|new|replace|text$)/i.test(key) && !/^old/i.test(key)) out.push(v); }
    else if (Array.isArray(v)) v.forEach((x) => walk(x, key));
    else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) walk(x, k);
  };
  walk(input);
  return out;
}
function addsApproval(input, abs) {
  const added = new Set(newTexts(input).flatMap((t) => [...approvalLines(t)]));
  if (!added.size) return null;
  let have = new Set();
  try { have = approvalLines(readFileSync(abs, "utf8")); } catch { /* new file */ }
  return [...added].find((l) => !have.has(l)) ?? null;
}

// Read-only git in a context repo (D101).
const READ_ONLY_GIT = new Set(["log", "show", "blame", "diff", "grep", "ls-files", "rev-parse", "cat-file", "describe", "shortlog"]);
const CONTEXT_PATH = /(^|\/)\.factory\/context(\/|$)/;

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
    const raw = String(input.command ?? "");
    const n = normalize(raw);
    const calls = gitCalls(raw);
    const variants = [raw, n, calls.map((c) => ["git", c.sub, ...c.args].join(" ")).join(" ; ")];
    const blocked = (rule, reason) => ({ rule, reason: `${reason}: blocked by the factory guard` });
    const first = (rules) => {
      for (const [rule, re, reason] of rules) if (variants.some((v) => re.test(v))) return blocked(rule, reason);
      return null;
    };
    const proc = procPath(n);
    if (proc) return blocked("secrets", `${proc}: /proc beyond cpuinfo, meminfo, loadavg, version and stat can expose process environments`);
    const ad = agentDir();
    const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const under = (d) => new RegExp(`(^|[^\\w.-])${esc(d)}(\\/|\\s|$|[;&|)])`).test(n);
    if ((process.env.PI_CODING_AGENT_DIR && under(ad)) || under(join(homedir(), ".pi"))) {
      return blocked("secrets", "reaching Pi's agent folder (its auth.json and models.json hold the provider keys)");
    }
    if (APPROVAL_WORDS.test(n) && !/^\s*(grep|egrep|fgrep|rg|git\s+grep)\b/.test(n)) {
      return blocked("approval", "writing an approval line (the human approves with /factory-approve, which logs it in decisions.tsv)");
    }
    const hit = first(BASH_RULES);
    if (hit) return hit;
    // Context repos: read-only git only, wherever the call points (D99, D101).
    const cwdInCtx = CONTEXT_PATH.test(resolve(cwd));
    for (const c of calls) {
      if (!(cwdInCtx || c.dirs.some((d) => /\.factory\/context\b/.test(d)))) continue;
      if (!READ_ONLY_GIT.has(c.sub) || c.args.some((a) => /^(--output|-O|--open-files-in-pager)/.test(a))) {
        return blocked("context", `git ${c.sub || ""} in a context repo (read-only: log, show, blame, diff, grep, ls-files, rev-parse, cat-file, describe, shortlog; it changes through its own team)`.replace("git  ", "git "));
      }
    }
    if (isWorker(cwd)) {
      const w = first(WORKER_BASH_RULES);
      if (w) return w;
    }
    if (hidesInstrument(cwd) && variants.some((v) => /\binstrument\//.test(v))) {
      return { rule: "wall", reason: "the instrument is hidden from workers (D21): blocked by the factory guard" };
    }
    return null;
  }
  const path = input.path ?? input.file_path ?? input.filePath;
  if (!path) return null;
  const r = rel(String(path), resolve(cwd), projectRoot(cwd) ?? resolve(cwd));
  const abs = isAbsolute(String(path)) ? String(path) : resolve(cwd, String(path));
  // Pi's provider keys (D101): auth.json and models.json in its agent folder.
  if ((abs.startsWith(agentDir() + "/") || abs === agentDir()) && /^(auth|models)\.json$/.test(basename(abs))) {
    return { rule: "secrets", reason: `${abs} holds Pi's provider keys: blocked by the factory guard` };
  }
  if ((tool === "write" || tool === "edit") && /(^|\/)decisions\.tsv$/.test(r)) {
    return { rule: "approval", reason: `${r} is the human's decision log (human.sh writes it): blocked by the factory guard` };
  }
  if (tool === "write" || tool === "edit") {
    const line = addsApproval(input, abs);
    if (line) return { rule: "approval", reason: `"${line}" is the human's to write (/factory-approve logs it in decisions.tsv): blocked by the factory guard` };
  }
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
