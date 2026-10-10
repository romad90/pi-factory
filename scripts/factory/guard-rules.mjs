// Command guard rules (D51). Pure functions, no I/O except existsSync, so
// they are unit-tested (tests/guard.test.mjs) and shared by the Pi extension
// .pi/extensions/factory-guard.ts, which blocks matching tool calls live.
//
// The guard is the first barrier, not the only one: whatever slips through,
// scripts/factory/patch-guard.sh rejects at integration, and CI gates the MR.
//
// check({ tool, input, cwd, home }) → null | { rule, reason }
import { existsSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

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
  ["secrets", /(^|[;&|]\s*)(printenv|env)\s*($|[;&|>])|\/proc\/\S*\/environ|\bsecurity\s+find-(generic|internet)-password\b/, "dumping environment or keychain secrets"],
  ["secrets", /\b(cat|less|more|head|tail|source|\.)(\s[^|;&]*)?[\s/]\.env(\.(?!example\b|sample\b|template\b|factory\b)[a-z]+)?(\s|$)/, "reading a .env file"],
  // Publishing and merging
  ["publish", /\b(npm|pnpm|yarn)\s+publish\b|\btwine\s+upload\b|\bcargo\s+publish\b|\bgem\s+push\b/, "publishing a package"],
  ["publish", /\b(gh|glab)\s+(pr|mr)\s+merge\b|\bgh\s+release\s+create\b|\bglab\s+release\s+create\b/, "merging or releasing"],
  // The guard itself
  ["guard", /FACTORY_GUARD\s*=/, "changing the guard"],
];

// Paths no agent writes or edits.
const PROTECTED_WRITE = /^(\.git\/|\.factory\/|scripts\/factory\/|\.pi\/|\.github\/|\.gitlab-ci\.yml$|\.husky\/|\.pre-commit-config\.yaml$|lefthook\.yml$)/;
// Paths no agent reads.
const SECRET_READ = /^\/(var\/)?run\/secrets(\/|$)|(^|\/)\.(ssh|aws|gnupg|kube|netrc|npmrc|pypirc)(\/|$)|(^|\/)\.env(\.[a-z]+)?$|(^|\/)id_(rsa|ed25519|ecdsa)(\.pub)?$/;
const SECRET_READ_OK = /(^|\/)\.env\.(example|sample|template|factory)$/;

function rel(p, cwd) {
  const abs = isAbsolute(p) ? p : resolve(cwd, p);
  return abs.startsWith(cwd + "/") ? abs.slice(cwd.length + 1) : abs;
}

// A worker's worktree has no instrument/ (sparse checkout, D35). From there,
// any route to it (git show, git log -p, another checkout) breaks the wall.
function hidesInstrument(cwd) {
  return existsSync(join(cwd, ".git")) && !existsSync(join(cwd, "instrument"));
}

export function check({ tool, input = {}, cwd = process.cwd() }) {
  if (process.env.FACTORY_GUARD === "off") return null;
  if (tool === "bash") {
    const cmd = String(input.command ?? "");
    for (const [rule, re, reason] of BASH_RULES) {
      if (re.test(cmd)) return { rule, reason: `${reason}: blocked by the factory guard` };
    }
    if (hidesInstrument(cwd) && /\binstrument\//.test(cmd)) {
      return { rule: "wall", reason: "the instrument is hidden from workers (D21): blocked by the factory guard" };
    }
    return null;
  }
  const path = input.path ?? input.file_path ?? input.filePath;
  if (!path) return null;
  const r = rel(String(path), cwd);
  if ((tool === "write" || tool === "edit") && PROTECTED_WRITE.test(r)) {
    return { rule: "paths", reason: `${r} belongs to the factory, CI or hooks: blocked by the factory guard` };
  }
  if (SECRET_READ.test(r) && !SECRET_READ_OK.test(r)) {
    return { rule: "secrets", reason: `${r} holds credentials: blocked by the factory guard` };
  }
  if (hidesInstrument(cwd) && /^instrument\//.test(r)) {
    return { rule: "wall", reason: "the instrument is hidden from workers (D21): blocked by the factory guard" };
  }
  return null;
}
