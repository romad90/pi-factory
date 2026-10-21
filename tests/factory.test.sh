#!/usr/bin/env bash
# End-to-end test of the factory scripts, without any model: installs the
# factory into a throwaway repo, then plays a mission by writing the files
# agents would write, and checks every STEP, gate and record on the way.
#
# Usage: bash tests/factory.test.sh        (needs bash, git, node)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; [ -n "${KEEP:-}" ] || trap 'rm -rf "$work"' EXIT
export FACTORY_NOTIFY=0 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
export PI_CODING_AGENT_DIR="$work/pi-agent"   # never this machine's Pi providers (D79)
export GIT_CONFIG_GLOBAL="$work/gitconfig"; printf '[commit]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

pass=0
t()      { printf '  ✓ %s\n' "$1"; pass=$((pass + 1)); }
fail()   { printf '  ✗ %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'; exit 1; }
expect_step() {                           # <code> <label>
  local out; out="$(bash scripts/factory/next.sh demo 2>&1 || true)"
  [ "$(head -1 <<<"$out")" = "STEP: $1" ] && t "$2 → STEP: $1" || fail "$2: expected STEP: $1" "$out"
}
gate_ok()   { bash scripts/factory/gate.sh mission demo >"$work/gate.log" 2>&1 && t "$1" || fail "$1" "$(cat "$work/gate.log")"; }
gate_fail() { if bash scripts/factory/gate.sh mission demo >"$work/gate.log" 2>&1; then fail "$1" "$(cat "$work/gate.log")"; fi
              grep -q -- "$2" "$work/gate.log" && t "$1" || fail "$1 (missing: $2)" "$(cat "$work/gate.log")"; }
brief() { bash scripts/factory/brief.sh "$@" | sed -n 's/^brief-id: //p'; }

echo "Install"
if [ "${FACTORY_TEST_MONOREPO:-0}" = 1 ]; then      # the same mission, as one project of a monorepo (D56)
  mono="$work/mono"; mkdir -p "$mono/projects/other"; git -C "$mono" init -q
  echo 'keep' > "$mono/projects/other/keep.js"; echo 'root' > "$mono/README.md"
  repo="$mono/projects/bot repo & co"; mkdir -p "$repo"; cd "$repo"
else
  repo="$work/bot repo & co"; mkdir -p "$repo"; cd "$repo"; git init -q
fi
mkdir -p src/tools; echo 'export const a = 1;' > src/tools/a.js; echo 'x' > README.md
git add -A; git commit -q -m init
bash "$root/scripts/factory/install-into.sh" "$repo" --pack api --pack batch >"$work/install.log" 2>&1 || fail "install-into.sh" "$(cat "$work/install.log")"
[ "$(git branch --show-current)" = "chore/install-pi-factory-$(cat "$root/.factory/VERSION")" ] && t "install lands on its own branch" || fail "install branch"
[ -z "$(git status --porcelain)" ] && grep -q '^chore(factory): install' <<<"$(git log -1 --format=%s)" && t "install is one commit" || fail "install commit"
[ -f .factory/ci/factory.gitlab-ci.yml ] && [ -f docs/factory/CHEATSHEET.md ] && t "CI template and cheat sheet installed" || fail "CI template"
[ -f docs/factory/prompts/audit-gaps.md ] && [ -f docs/factory/prompts/security-audit.md ] && t "read-only prompts installed" || fail "prompts"
[ -f docs/agents/factory.md ] && grep -q 'docs/agents/factory.md' AGENTS.md && ! grep -q 'END OF BRIEF' AGENTS.md \
  && t "AGENTS.md gets a pointer, the factory rules live in docs/agents/factory.md" || fail "AGENTS.md pointer" "$(cat AGENTS.md)"
bash scripts/factory/brief.sh worker probe 01 HEAD | grep -q '^Read: docs/agents/factory.md' && ! bash scripts/factory/brief.sh worker probe 01 HEAD | grep -q 'AGENTS.md' \
  && t "briefs name the factory rules, not AGENTS.md (already in context)" || fail "brief read list"
[ -f docs/agents/contract-checklist-api.md ] && [ -f docs/agents/quality-bar-batch.md ] && [ ! -f docs/agents/contract-checklist-bots.md ] \
  && t "only the requested practice packs are installed" || fail "packs" "$(ls docs/agents)"
bad_fm="$(node -e '
const fs=require("fs"),path=require("path");const out=[];
const walk=(d)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);
  if(e.isDirectory())walk(p);else if(p.endsWith(".md")){const m=fs.readFileSync(p,"utf8").match(/^---\n([\s\S]*?)\n---/);
  if(m)for(const l of m[1].split("\n")){const k=l.match(/^[\w-]+:\s+(.*)$/);if(k&&!/^["\x27[{|>]/.test(k[1])&&/: /.test(k[1]))out.push(p+": "+l);}}}};
walk(".pi");console.log(out.join("\n"));')"
[ -z "$bad_fm" ] && t "every installed prompt, agent and skill has valid frontmatter (no unquoted ': ')" || fail "frontmatter YAML" "$bad_fm"
node -e 'const r=require("./.pi/settings.json").retry; process.exit(r && r.enabled && r.maxRetries >= 1 ? 0 : 1)' \
  && t "Pi retries on rate limits in an installed repo" || fail "retry settings" "$(cat .pi/settings.json)"
grep -q 'every docs/agents/quality-bar-\*.md' .factory/briefs/code-steward.md && t "the steward brief reads the packs' quality bars" || fail "steward pack brief"
mkdir -p "$work/home/.pi/agent/extensions/subagent"; echo '{"timeoutMs": 600000, "parallel": {"concurrency": 1}}' > "$work/home/.pi/agent/extensions/subagent/config.json"
HOME="$work/home" bash "$root/scripts/factory/install-pi-config.sh" >/dev/null 2>&1
node -e 'const c=require(process.argv[1]); process.exit(c.timeoutMs===7200000 && c.parallel.concurrency===1 && /factory-worktree-hook/.test(c.worktreeSetupHook) ? 0 : 1)' "$work/home/.pi/agent/extensions/subagent/config.json" \
  && t "pi config: waves may run 2 h (D72), concurrency and hook kept" || fail "pi config timeout" "$(cat "$work/home/.pi/agent/extensions/subagent/config.json")"
if bash "$root/scripts/factory/install-into.sh" "$repo" --pack nope --no-branch >/dev/null 2>&1; then fail "unknown pack must fail"; fi
t "an unknown pack is refused"

# Fake models: author/worker one family, critic/judges another.
for a in .pi/agents/factory/*.md; do
  case "$(basename "$a")" in
    factory-contract-critic.md|factory-reviewer.md|factory-review-axis.md|factory-validator.md|factory-code-steward.md) m=gw/judge-1 ;;
    *) m=gw/maker-1 ;;
  esac
  sed -i.bak "s|^model: .*|model: $m|" "$a" && rm -f "$a.bak"
done
node -e '
const fs=require("fs"); const f=".factory/model-families.json"; const j=JSON.parse(fs.readFileSync(f,"utf8"));
j.families.push({match:"*maker*",family:"makers"},{match:"*judge*",family:"judges"}); fs.writeFileSync(f, JSON.stringify(j,null,2));
const s=".pi/settings.json"; const k=JSON.parse(fs.readFileSync(s,"utf8")); k.subagents.modelScope.allow=["gw/*"]; fs.writeFileSync(s, JSON.stringify(k,null,2));'
node scripts/factory/models-lint.mjs >"$work/lint.log" 2>&1 && t "models-lint passes with separated families" || fail "models-lint" "$(cat "$work/lint.log")"
export PI_FACTORY_MODELS="$work/home/models.json"
node scripts/factory/models-profile.mjs capture >/dev/null && grep -q 'gw/judge-1' "$PI_FACTORY_MODELS" && t "models profile captured from a configured repo" || fail "models capture"
repo2="$work/second repo"; mkdir -p "$repo2"; git -C "$repo2" init -q; echo x > "$repo2/README.md"; git -C "$repo2" add -A; git -C "$repo2" commit -q -m init
bash "$root/scripts/factory/install-into.sh" "$repo2" >"$work/install2.log" 2>&1 || fail "second install" "$(cat "$work/install2.log")"
(cd "$repo2" && node scripts/factory/models-lint.mjs >/dev/null 2>&1) && t "a new repo gets the models from the profile at install" || fail "models apply" "$(cat "$work/install2.log")"
unset PI_FACTORY_MODELS
mkdir -p "$repo2/sub"; echo y > "$repo2/sub/y.js"; echo z > "$repo2/z.js"; git -C "$repo2" add -A; git -C "$repo2" commit -q -m sub
echo 'local change' >> "$repo2/z.js"                # outside the project: not ours, must stay as it is
bash "$root/scripts/factory/install-into.sh" "$repo2/sub" >"$work/install3.log" 2>&1 || fail "monorepo project install" "$(cat "$work/install3.log")"
[ -z "$(git -C "$repo2" show --name-only --format= HEAD | grep -v '^sub/')" ] && [ -f "$repo2/sub/.factory/VERSION" ] \
  && git -C "$repo2" diff --quiet -- sub && ! git -C "$repo2" diff --quiet -- z.js \
  && grep -q '"projectRootResolution": "nearest"' "$repo2/sub/.pi/settings.json" \
  && grep -q '^## Monorepo project' "$repo2/sub/AGENTS.md" && grep -q 'folder `sub`' "$repo2/sub/AGENTS.md" \
  && t "a monorepo project installs into its folder only" || fail "monorepo install scope" "$(cat "$work/install3.log"; git -C "$repo2" show --stat HEAD)"
mkdir -p "$repo2/kid"; echo k > "$repo2/kid/k.js"
bash "$root/scripts/factory/install-into.sh" "$repo2/sub" --no-branch >/dev/null 2>&1
[ "$(grep -c '^## Monorepo project' "$repo2/sub/AGENTS.md")" = 1 ] && t "monorepo: the 'repo root = project folder' note is written once" || fail "monorepo note twice"
printf '# Team\n\n## Agentic factory\n\nold factory rules\n' > "$repo2/kid/AGENTS.md"
bash "$root/scripts/factory/install-into.sh" "$repo2/kid" --no-branch --ci child >"$work/install4.log" 2>&1 || fail "child install" "$(cat "$work/install4.log")"
grep -q "old factory rules" "$repo2/kid/AGENTS.md" && ! grep -q "docs/agents/factory.md" "$repo2/kid/AGENTS.md" && grep -q "older install" "$work/install4.log" \
  && t "an old full factory section is left alone, with a note to replace it" || fail "old AGENTS section" "$(cat "$repo2/kid/AGENTS.md")"
ci="$repo2/kid/.factory/ci/factory.gitlab-ci.yml"
[ "$(grep -c 'parent_pipeline" && \$FACTORY_MR_TARGET$' "$ci")" = 4 ] && ! grep -q 'merge_request_event' "$ci" && grep -q 'strategy: depend' "$ci" \
  && grep -q 'FACTORY_MR_LABELS' "$root/scripts/factory/gate.sh" \
  && t "--ci child: jobs run in the child pipeline the parent starts, with the MR passed down" || fail "child CI" "$(head -40 "$ci")"
git add -A; git commit -q -m "chore: models"; base0="$(git rev-parse HEAD)"

if [ -n "${mono:-}" ]; then
  pre="projects/bot repo & co"
  grep -q '^factory-gate-projects-bot-repo-co:$' .factory/ci/factory.gitlab-ci.yml && grep -q 'changes: \["projects/bot repo & co/\*\*/\*"\]' .factory/ci/factory.gitlab-ci.yml \
    && grep -q '"projectRootResolution": "nearest"' .pi/settings.json \
    && t "monorepo: CI jobs named after the project, run only when it changed; Pi resolves the nearest project" || fail "monorepo CI" "$(head -40 .factory/ci/factory.gitlab-ci.yml)"
  printf 'diff --git a/%s/.github/ci.yml b/%s/.github/ci.yml\nnew file mode 100644\n--- /dev/null\n+++ b/%s/.github/ci.yml\n@@ -0,0 +1 @@\n+on: push\n' "$pre" "$pre" "$pre" > "$work/root-evil.patch"
  bash -c '. scripts/factory/lib.sh; project_patch "$1" "$2"' _ "$work/root-evil.patch" "$work/norm.patch" \
    && grep -q '^+++ b/.github/ci.yml' "$work/norm.patch" && ! bash scripts/factory/patch-guard.sh "$work/norm.patch" >/dev/null \
    && t "monorepo: a root-relative patch is made project-relative, so the patch guard still sees CI paths" || fail "project_patch" "$(cat "$work/norm.patch")"
  printf 'diff --git a/%s/src/a.js b/%s/src/a.js\n--- a/%s/src/a.js\n+++ b/%s/src/a.js\n@@ -1 +1 @@\n-x\n+y\ndiff --git a/projects/other/keep.js b/projects/other/keep.js\n--- a/projects/other/keep.js\n+++ b/projects/other/keep.js\n@@ -1 +1 @@\n-keep\n+gone\n' "$pre" "$pre" "$pre" "$pre" > "$work/leak.patch"
  if bash -c '. scripts/factory/lib.sh; project_patch "$1" "$2"' _ "$work/leak.patch" "$work/norm2.patch"; then fail "a patch reaching a sibling project must be refused"; fi
  t "monorepo: a patch reaching outside the project is refused"
  printf 'diff --git a/projects/other/new.js b/projects/other/new.js\nnew file mode 100644\n--- /dev/null\n+++ b/projects/other/new.js\n@@ -0,0 +1 @@\n+x\n' > "$work/sibling-only.patch"
  if bash -c '. scripts/factory/lib.sh; project_patch "$1" "$2"' _ "$work/sibling-only.patch" "$work/n3.patch"; then fail "a patch only touching a sibling must be refused"; fi
  t "monorepo: a patch touching only a sibling project is refused, not moved into ours"
  printf 'diff --git "a/%s/src/\\303\\251.js" "b/%s/src/\\303\\251.js"\nnew file mode 100644\n--- /dev/null\n+++ "b/%s/src/\\303\\251.js"\n@@ -0,0 +1,2 @@\n+-- a/%s/x\n+y\n' "$pre" "$pre" "$pre" "$pre" > "$work/quoted.patch"
  bash -c '. scripts/factory/lib.sh; project_patch "$1" "$2"' _ "$work/quoted.patch" "$work/n4.patch" \
    && grep -q '^+++ "b/src/\\303\\251.js"$' "$work/n4.patch" && grep -qF -- "+-- a/$pre/x" "$work/n4.patch" \
    && t "monorepo: quoted paths are rewritten, hunk lines that look like headers are left alone" || fail "quoted rewrite" "$(cat "$work/n4.patch")"
fi

pg_blocks() {                          # <label> <patch text>
  printf '%b' "$2" > "$work/pg.patch"
  if bash scripts/factory/patch-guard.sh "$work/pg.patch" >"$work/pg.log"; then fail "$1" "$(cat "$work/pg.patch")"; fi
  t "$1"
}
pg_blocks "patch guard: an instrument path with a space" 'diff --git a/instrument/x y.txt b/instrument/x y.txt\nnew file mode 100644\n--- /dev/null\n+++ b/instrument/x y.txt\n@@ -0,0 +1 @@\n+x\n'
pg_blocks "patch guard: a quoted (non-ASCII) instrument path" 'diff --git "a/instrument/\\303\\251.txt" "b/instrument/\\303\\251.txt"\nnew file mode 100644\n--- /dev/null\n+++ "b/instrument/\\303\\251.txt"\n@@ -0,0 +1 @@\n+x\n'
pg_blocks "patch guard: a rename out of the instrument" 'diff --git a/instrument/s.txt b/src/leak.txt\nsimilarity index 100%%\nrename from instrument/s.txt\nrename to src/leak.txt\n'
pg_blocks "patch guard: a test renamed away" 'diff --git a/tests/a.test.js b/src/a.js\nsimilarity index 100%%\nrename from tests/a.test.js\nrename to src/a.js\n'
pg_blocks "patch guard: a new symbolic link" 'diff --git a/src/l b/src/l\nnew file mode 120000\n--- /dev/null\n+++ b/src/l\n@@ -0,0 +1 @@\n+../instrument\n\\ No newline at end of file\n'
printf 'diff --git a/tests/a.test.js b/tests/b.test.js\nsimilarity index 100%%\nrename from tests/a.test.js\nrename to tests/b.test.js\n' > "$work/pg.patch"
bash scripts/factory/patch-guard.sh "$work/pg.patch" >/dev/null && t "patch guard: moving a test file is fine" || fail "test move" "$(bash scripts/factory/patch-guard.sh "$work/pg.patch")"

echo "Frozen paths (D61)"
mkdir -p .scratch/maint/issues .scratch/frz
printf '# Maint\n**Intent:** maintenance\n\n## Validation contract\n\n### VAL-M-001: as today\n**Kind:** code\n' > .scratch/maint/spec.md
for n in 01-doc 02-tests 03-more; do printf '# %s\n## Covers: enabler\nhousekeeping\n' "$n" > .scratch/maint/issues/$n.md; done
git add .scratch; git commit -q -m "test: maintenance mission"
src_patch='diff --git a/src/tools/a.js b/src/tools/a.js\n--- a/src/tools/a.js\n+++ b/src/tools/a.js\n@@ -1 +1 @@\n-export const a = 1;\n+export const a = 2;\n'
printf '%b' "$src_patch" > "$work/fz.patch"
if bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission maint >"$work/pg.log"; then fail "maintenance must freeze src/" "$(cat "$work/pg.log")"; fi
grep -q '^BLOCKED frozen: src/tools/a.js' "$work/pg.log" && t "maintenance mission: src/ is frozen by default" || fail "frozen src" "$(cat "$work/pg.log")"
bash scripts/factory/patch-guard.sh "$work/fz.patch" >/dev/null && t "without a mission, the same patch is clean" || fail "frozen leaks without mission"
printf 'diff --git a/src/tools/a.test.js b/src/tools/a.test.js\nnew file mode 100644\n--- /dev/null\n+++ b/src/tools/a.test.js\n@@ -0,0 +1 @@\n+it("a", () => {});\n' > "$work/fz.patch"
bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission maint >/dev/null && t "frozen: a characterization test next to the code is allowed" || fail "frozen test" "$(bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission maint)"
printf '# Frz\n**Intent:** maintenance\n\n## Frozen paths\n- `deploy/` — infra, owned elsewhere\n- *.lock\n\n## Validation contract\n' > .scratch/frz/spec.md
[ "$(bash -c '. scripts/factory/lib.sh; frozen_paths .scratch/frz/spec.md' | paste -sd' ' -)" = 'deploy/ *.lock' ] && t "frozen: the spec section replaces the default (prefix and glob)" || fail "frozen parse"
printf '%b' "$src_patch" > "$work/fz.patch"
bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission frz >/dev/null && t "frozen: src/ is free when the section doesn't list it" || fail "frozen section"
pg_frozen() { printf 'diff --git a/%s b/%s\nnew file mode 100644\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$1" "$1" "$1" > "$work/fz.patch"
  if bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission frz >/dev/null; then fail "frozen: $1 must be refused"; fi; t "frozen: $1 is refused ($2)"; }
pg_frozen deploy/values.yaml prefix; pg_frozen yarn.lock glob
printf '# Frz\n**Intent:** maintenance\n\n## Frozen paths\n- none\n' > .scratch/frz/spec.md
printf '%b' "$src_patch" > "$work/fz.patch"
bash scripts/factory/patch-guard.sh "$work/fz.patch" --mission frz >/dev/null && t "frozen: '- none' unfreezes a maintenance mission" || fail "frozen none"
rm -rf .scratch/frz
cmds0="$(git rev-parse HEAD)"; printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD="true"\n' > .factory/commands.env; git commit -qam "test: commands"
if bash scripts/factory/integrate.sh maint 01-doc "$work/fz.patch" >"$work/int.log" 2>&1; then fail "integration must refuse a frozen path" "$(cat "$work/int.log")"; fi
[ "$(bash -c '. scripts/factory/lib.sh; verdict_field .scratch/maint/verdicts/01-doc-code.md Brief')" = patch-guard ] \
  && grep -q 'frozen: src/tools/a.js' .scratch/maint/verdicts/01-doc-code.md && [ "$(cat src/tools/a.js)" = 'export const a = 1;' ] \
  && t "integrate refuses a frozen change before applying it (a failed round with the reason)" || fail "integrate frozen" "$(cat "$work/int.log")"
bash scripts/factory/brief.sh worker maint 01-doc > "$work/brief.txt"
grep -qF 'tests under them are allowed): `src/`.' "$work/brief.txt" && grep -qF 'lint (`true`' "$work/brief.txt" \
  && grep -qF 'scripts/factory/self-check.sh maint' "$work/brief.txt" \
  && t "the worker brief carries the frozen paths, the lint command and the self-check" || fail "brief" "$(cat "$work/brief.txt")"
# Cache: what changes per ticket (ticket, commit) comes after the fixed instructions,
# so every worker of a mission shares the same prompt prefix.
first_var="$(grep -nE '01-doc|[0-9a-f]{40}' "$work/brief.txt" | head -1 | cut -d: -f1)"
last_fixed="$(grep -n 'last self-check line' "$work/brief.txt" | cut -d: -f1)"
[ -n "$first_var" ] && [ "$first_var" -gt "$last_fixed" ] && t "the worker brief puts the ticket and commit last (shared cache prefix)" \
  || fail "brief order" "$(cat "$work/brief.txt")"
r="$(bash scripts/factory/resolve.sh maint 01-doc 'Can I export the helper from src/tools/a.js so the test can call it?' || true)"
[ "${r%%$'\t'*}" = frozen ] && grep -q "changes src/ is refused" <<<"$r" && t "resolver: changing a frozen path is refused by the contract's rule (D70)" || fail "resolver frozen" "$r"
r="$(bash scripts/factory/resolve.sh maint 01-doc 'The contract says 3 retries but the code does 5. Which one?' || true)"
[ -z "$r" ] && t "resolver: a contract question always goes to the human" || fail "resolver contract" "$r"
git checkout -q "$cmds0" -- .factory/commands.env; git commit -qm "test: reset commands"

echo "Mission: planning"
m=.scratch/demo
expect_step grill "no spec"
mkdir -p $m/issues
cat > $m/spec.md <<'SPEC'
# Demo
**Intent:** feature

Users get a greeting.

## Validation contract

### VAL-HELLO-001: greets
**Kind:** behavior
Given a user, when they say hi, then the bot says hello.

### VAL-HELLO-002: counts
**Kind:** code
Given two greetings, when counted, then the count is 2.
SPEC
expect_step contract "contract without critique"
echo "No findings. Critique result: approve" > $m/contract-critique.md
expect_step approve "critique present, not approved"
bash scripts/factory/human.sh approve demo >/dev/null
grep -qE '^\*\*Contract approved:\*\* [0-9]{4}-' $m/spec.md && t "/factory-approve writes the approval line" || fail "approve line"
[ -z "$(git status --porcelain -- .scratch)" ] && t "approval is checkpointed" || fail "approval not committed"
grep -q $'\tapprove\t' $m/decisions.tsv && t "approval logged in decisions.tsv" || fail "decisions.tsv"

bash scripts/factory/human.sh amend demo "count must start at zero" >/dev/null
expect_step contract "pending amendment reruns the contract wave"
grep -q 'Contract approved' $m/spec.md && fail "amend must remove approval" || t "amend removes approval"
bash scripts/factory/workflow.sh contract demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
[ -f "$wf" ] && grep -q 'const ITEMS' "$wf" && t "contract wave written to a file ($(basename "$wf"))" || fail "workflow file"
grep -q '^\*\*Status:\*\* sent' $m/amendments/*.md && t "amendment marked sent" || fail "amendment status"
bash scripts/factory/human.sh approve demo >/dev/null
expect_step tickets "approved, no tickets"
bash scripts/factory/workflow.sh tickets demo all >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"agent": "factory-ticket-writer"' "$wf" && grep -q 'write the mission' "$wf" && t "tickets come from the ticket writer" || fail "ticket writer wave" "$(cat "$wf")"
# What the ticket writer would write:
cat > $m/issues/01-hello.md <<'TK'
# 01 hello
**Size:** S
## Covers
VAL-HELLO-001
TK
cat > $m/issues/02-count.md <<'TK'
# 02 count
**Size:** L
## Covers
VAL-HELLO-002
## Blocked by
01
TK
expect_step approve-tickets "proposed tickets wait for a human"
bash scripts/factory/human.sh approve demo tickets >/dev/null
grep -q $'\tapprove-tickets\t' $m/decisions.tsv && t "/factory-approve <f> tickets logs the approval" || fail "approve tickets"
expect_step setup "no FACTORY_TEST_CMD"
printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD="test -f src/tools/a.js"\n' > .factory/commands.env
git add -A; git commit -q -m "chore: commands"
expect_step build "tests configured"

echo "Mission: build and review"
bash scripts/factory/workflow.sh build-wave demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"key": "01-hello"' "$wf" && ! grep -q '"key": "02-count"' "$wf" && t "build wave holds only unblocked tickets" || fail "build wave"
grep -q 'patchOf' "$wf" && t "build wave returns patch paths" || fail "patchOf"
[ -z "$(git status --porcelain --untracked-files=all -- .scratch)" ] && t "generated workflow is committed (tree stays clean)" || fail "workflow file left untracked"

# A provider error (429…) is not a round: the mission pauses (D58).
bash scripts/factory/record-no-patch.sh demo 01-hello --provider "429 rate limit" >/dev/null
[ ! -f $m/verdicts/01-hello-code.md ] && grep -q "429 rate limit" $m/state/PAUSED.md \
  && t "provider error = pause, no round" || fail "provider error must pause without a round"
expect_step paused "paused after provider error"
bash scripts/factory/pause.sh resume demo >/dev/null
# Wave size from commands.env (D58).
[ "$(env -u FACTORY_MAX_PARALLEL bash -c 'printf "FACTORY_MAX_PARALLEL=1\n" >> .factory/commands.env; . scripts/factory/lib.sh; echo $FACTORY_MAX_PARALLEL')" = 1 ] \
  && t "wave size read from commands.env" || fail "FACTORY_MAX_PARALLEL from commands.env"
git checkout -q -- .factory/commands.env

# Round 1: no patch. Round 2: failing integration → heavy worker.
bash scripts/factory/record-no-patch.sh demo 01-hello >/dev/null
[ -f $m/verdicts/01-hello-code.r1.md ] && t "no patch = failed round 1 (recorded)" || fail "no-patch round"
echo 'garbage' > bad.patch
if bash scripts/factory/integrate.sh demo 01-hello bad.patch >/dev/null 2>&1; then fail "bad patch must fail"; fi
[ "$(bash -c '. scripts/factory/lib.sh; verdict_round .scratch/demo/verdicts/01-hello-code.md')" = 2 ] && t "unappliable patch = round 2" || fail "round 2"
rm bad.patch
bash scripts/factory/workflow.sh build-wave demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"agent": "factory-worker-heavy"' "$wf" && t "round 2 routes to the heavy worker" || fail "heavy routing"
jscheck() { { echo '(async () => {'; sed 1d "$1"; echo '})'; } > "$work/wf-check.js"; node --check "$work/wf-check.js"; }
grep -q '^const GATE = null;' "$wf" && jscheck "$wf" && t "build wave: no self-check gate by default, script parses" || fail "gate default" "$(head -5 "$wf")"
git rm -q --cached "$wf" >/dev/null 2>&1; rm -f "$wf"; git commit -qm "test: drop wave" >/dev/null 2>&1 || true
FACTORY_SELF_CHECK_GATE=1 bash scripts/factory/workflow.sh build-wave demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q 'scripts/factory/self-check.sh demo' "$wf" && grep -q 'resume: r.runId' "$wf" && jscheck "$wf" \
  && t "build wave: FACTORY_SELF_CHECK_GATE=1 gates each worker on its self-check, one same-session retry (D78)" || fail "gate on" "$(sed -n 2,40p "$wf")"
gcmd="$(node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8"); process.stdout.write(JSON.parse(s.match(/^const GATE = (.*);$/m)[1]).command)' "$wf")"
(cd "$(git rev-parse --show-toplevel)" && bash -c "$gcmd") > "$work/gate.log" 2>&1 || true
grep -q '^SELF-CHECK: ' "$work/gate.log" && t "build wave: the gate command runs from the worktree root, project path quoted" || fail "gate command" "$gcmd: $(cat "$work/gate.log")"

# The wave returned no patch path: the work is in the worker's worktree,
# which pi-subagents keeps on a pi-subagents/<ticket>-… branch (D60).
sleep 1
wt="$work/wt-01"; git worktree add -q -b pi-subagents/01-hello-abc123-s0-t0 "$wt" HEAD
wt_project="$wt/$(git rev-parse --show-prefix)"
echo 'export const hello = () => "hello";' > "$wt_project/src/tools/hello.js"
# D65: the hook gives the worker the installed dependencies, and they never reach the patch.
mkdir -p node_modules/fake-dep; echo 'module.exports = 1;' > node_modules/fake-dep/index.js
printf '{"repoRoot":"%s","worktreePath":"%s","index":0}' "$(git rev-parse --show-toplevel)" "$wt" \
  | FACTORY_PROJECT_PREFIX="$(git rev-parse --show-prefix)" node scripts/factory/worktree-hook.mjs > "$work/hook.json" \
  || fail "worktree hook runs" "$(cat "$work/hook.json")"
[ -L "$wt_project/node_modules" ] && [ -f "$wt_project/node_modules/fake-dep/index.js" ] \
  && grep -q 'node_modules' "$work/hook.json" && t "the worktree hook links the installed dependencies (D65)" \
  || fail "dependency link" "$(ls -la "$wt_project"; cat "$work/hook.json")"
# D66: the worker runs integration's checks itself before handing over.
sc() { (cd "$wt_project" && bash scripts/factory/self-check.sh demo) > "$work/sc.log" 2>&1; }
sc && grep -q '^SELF-CHECK: PASS' "$work/sc.log" && t "self-check passes in the worktree, dependency link left out of the guarded change" \
  || fail "self-check pass" "$(cat "$work/sc.log")"
git -C "$wt" diff --cached --quiet && t "self-check leaves the worker's index alone" || fail "self-check staged files" "$(git -C "$wt" status --short)"
cp "$wt_project/src/tools/hello.js" "$work/hello.bak"; echo '// eslint-disable-next-line no-console' >> "$wt_project/src/tools/hello.js"
if sc; then fail "self-check must refuse a silenced check" "$(cat "$work/sc.log")"; fi
grep -q '^SELF-CHECK: FAIL guard' "$work/sc.log" && grep -q 'silence' "$work/sc.log" && t "self-check runs the patch guard: a silenced check fails before handover" \
  || fail "self-check guard" "$(cat "$work/sc.log")"
cp "$work/hello.bak" "$wt_project/src/tools/hello.js"; mv "$wt_project/src/tools/a.js" "$work/a.js.bak"
if sc; then fail "self-check must fail on red tests" "$(cat "$work/sc.log")"; fi
grep -q '^SELF-CHECK: FAIL tests' "$work/sc.log" && t "self-check fails on red tests, with the end of their output" || fail "self-check tests" "$(cat "$work/sc.log")"
grep -q '^FAIL tests ' "$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/drafts/demo/01-hello.patch.status" \
  && t "self-check records its last result next to the draft (D78)" || fail "self-check status"
mv "$work/a.js.bak" "$wt_project/src/tools/a.js"
# D73: every self-check run saves the change as a draft that outlives the worktree.
sc || fail "self-check pass again" "$(cat "$work/sc.log")"
draft="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/drafts/demo/01-hello.patch"
[ -s "$draft" ] && grep -q '^+++ b/.*src/tools/hello.js' "$draft" && ! grep -q 'node_modules' "$draft" \
  && t "self-check saves the worker's change as a draft patch in the shared git folder (D73)" || fail "draft patch" "$(ls -la "$(dirname "$draft")" 2>&1; cat "$draft" 2>&1)"
git -C "$wt" switch -q -c not-a-worker
[ "$(bash scripts/factory/locate-patch.sh demo 01-hello 2>/dev/null)" = "$draft" ] \
  && t "locate-patch falls back to the draft when no worktree is left (D73)" || fail "draft fallback" "$(bash scripts/factory/locate-patch.sh demo 01-hello 2>&1)"
git -C "$wt" switch -q pi-subagents/01-hello-abc123-s0-t0; git branch -q -D not-a-worker
printf 'Tried the default export; ruled out a class (the test imports a function).\n' | (cd "$wt_project" && bash scripts/factory/journal.sh demo) >/dev/null \
  || fail "journal.sh" "worker could not write its journal"
bash scripts/factory/integrate.sh demo 01-hello null >"$work/int.log" 2>&1 || fail "integrate 01 from the worktree" "$(cat "$work/int.log")"
grep -q '^## Round 3 .*integrated' $m/journal/01-hello.md && grep -q 'ruled out a class' $m/journal/01-hello.md \
  && t "the worker's journal moves into the mission under its round (D84)" || fail "journal" "$(cat $m/journal/01-hello.md 2>&1)"
[ ! -e "$draft" ] && [ ! -e "$draft.status" ] && t "a successful integration removes the ticket's draft and its status" || fail "draft left after integration"
t "null patch is rebuilt from the worker's worktree"
! git show --stat HEAD~1 | grep -q 'node_modules\|\.env\.factory' && t "the rebuilt patch leaves out the dependency link and .env.factory" \
  || fail "dependency link in the patch" "$(git show --stat HEAD~1)"
rm -rf node_modules
git worktree remove --force "$wt"; git branch -q -D pi-subagents/01-hello-abc123-s0-t0
c1="$(cat $m/state/01-hello.integrated)"
grep -q '^feat(demo): 01-hello' <<<"$(git log -1 --skip=1 --format=%s)" && t "integration commit is a Conventional Commit" || fail "integration message: $(git log -3 --format=%s)"
expect_step review "integrated ticket waits for review"

# D81: a review of an older commit is stale: kept aside, not a round.
printf '# Verdict: 01-hello\n**Result:** FAIL\n**Commit:** %s\n\n## Issues\n- [blocking] README only\n' "$(git rev-parse HEAD~3)" > $m/verdicts/01-hello-code.md
bash scripts/factory/collect.sh demo > "$work/collect.log"
grep -q 'stale: reviews' "$work/collect.log" && [ -f $m/state/01-hello.stale-verdict.md ] && [ ! -f $m/verdicts/01-hello-code.r3.md ] \
  && t "a verdict on an older commit than the integration is stale, not a round (D81)" || fail "stale verdict" "$(cat "$work/collect.log"; ls $m/verdicts $m/state)"
expect_step review "the ticket of a stale verdict is reviewed again"
# D69: a verdict without a Result line goes back to review once, it is not a round.
printf '# Verdict: 01-hello\n**Commit:** %s\n\nLooks fine to me.\n' "$c1" > $m/verdicts/01-hello-code.md
bash scripts/factory/collect.sh demo > "$work/collect.log"
grep -q 'sent back to review' "$work/collect.log" && [ ! -f $m/verdicts/01-hello-code.md ] && [ ! -f $m/verdicts/01-hello-code.r3.md ] \
  && t "a verdict without a Result line is sent back to review, not counted as a round" || fail "invalid verdict" "$(cat "$work/collect.log"; ls $m/verdicts)"
expect_step review "the slipped verdict's ticket is reviewed again"
bid="$(brief reviewer demo 01-hello "$c1")"
cat > $m/verdicts/01-hello-code.md <<V
# Verdict: 01-hello — round 1
**Result:** PASS
**Commit:** $c1
**Model:** gpt-4o
**Brief:** $bid

## Assertions
- VAL-HELLO-001: PASS — tests/hello.test.js "greets"
V
gate_fail "uncollected verdict is rejected" "run collect.sh"
bash scripts/factory/collect.sh demo >/dev/null
grep -q '^# Verdict: 01-hello — round 3$' $m/verdicts/01-hello-code.md && t "collect.sh numbers the round from history (3, not the agent's 1)" || fail "round rewrite" "$(head -3 $m/verdicts/01-hello-code.md)"
grep -q '^\*\*Model:\*\* gw/judge-1 (configured for factory-reviewer)' $m/verdicts/01-hello-code.md && t "model is the configured one, not 'gpt-4o'" || fail "model rewrite"
bash scripts/factory/collect.sh demo >/dev/null
[ ! -f $m/verdicts/01-hello-code.r4.md ] && t "collect.sh is idempotent" || fail "collect idempotent"
[ ! -f $m/state/01-hello.sent-back ] && [ ! -f $m/state/01-hello.invalid-verdict.md ] && t "a valid verdict clears the send-back" || fail "send-back cleared" "$(ls $m/state)"

# D67: a misspelled mission or a switched branch stops before any step.
out="$(bash scripts/factory/next.sh dmeo 2>&1 || true)"
[ "$(head -1 <<<"$out")" = "STEP: blocked" ] && grep -q "Did you mean 'demo'" <<<"$out" && [ ! -d .scratch/dmeo ] \
  && t "a misspelled mission is refused with the closest name" || fail "mission typo" "$out"
bash scripts/factory/doctor.sh --quick dmeo > "$work/pf.log" 2>&1 && fail "pre-flight must refuse a misspelled mission" "$(cat "$work/pf.log")"
grep -q "Did you mean 'demo'" "$work/pf.log" && t "pre-flight refuses a misspelled mission" || fail "pre-flight typo" "$(cat "$work/pf.log")"
out="$(bash scripts/factory/record-no-patch.sh dmeo 01-hello 2>&1 || true)"
grep -q "Did you mean 'demo'" <<<"$out" && t "record-no-patch refuses a misspelled mission with the closest name" || fail "record-no-patch typo" "$out"
orig="$(git branch --show-current)"
git switch -q -c elsewhere "$(git log -1 --format=%H -- "$m")^"
out="$(bash scripts/factory/next.sh demo 2>&1 || true)"
[ "$(head -1 <<<"$out")" = "STEP: blocked" ] && grep -q "is on branch '$orig'" <<<"$out" \
  && t "a checkout switched to another branch is refused, with the mission's branch" || fail "wrong branch" "$out"
git switch -q "$orig"; git branch -q -D elsewhere

# Ticket 02 asks a decision.
bash scripts/factory/human.sh ask demo 02-count --stdin >/dev/null <<'Q'
Delete old counts in production? A) yes B) no
Q
expect_step decide "open question stops the mission"
grep -q 'irreversib\|production' <<<"$(cat $m/state/open-question.md)" && t "a production question is never auto-answered" || fail "resolver let a production question through"
# D68: the text goes through a quoted heredoc: backticks, $ and quotes stay text.
bash scripts/factory/human.sh decide demo --stdin >/dev/null <<'A'
B, keep data: `rm` is irreversible, "$HOME" stays text
A
grep -q $'02-count\tdecide\tDelete old counts' $m/decisions.tsv && t "/factory-decide logs question and answer" || fail "decide log" "$(cat $m/decisions.tsv)"
grep -qF 'B, keep data: `rm` is irreversible, "$HOME" stays text' $m/decisions.tsv && t "/factory-decide keeps backticks, quotes and \$ as text (--stdin)" || fail "decide quoting" "$(cat $m/decisions.tsv)"
[ -z "$(git status --porcelain -- $m)" ] && t "a decision is committed with the mission state" || fail "decision not committed" "$(git status --short)"
expect_step build "answered, ticket 02 builds"

# D70: settled questions are answered without the human.
ask() { bash scripts/factory/human.sh ask demo 02-count --stdin > "$work/ask.log" <<<"$1"; }
ask 'Should I install vitest as a dev dependency? A) yes B) no'
grep -q '^AUTO-ANSWERED (dependencies)' "$work/ask.log" && [ ! -f $m/state/open-question.md ] \
  && grep -q $'02-count\tauto\tShould I install vitest.*\tfactory (dependencies)\tunreviewed$' $m/decisions.tsv \
  && t "resolver: a dependency question is answered by the rule, logged as auto" || fail "resolver deps" "$(cat "$work/ask.log"; tail -2 $m/decisions.tsv)"
expect_step build "an auto-answer lets the ticket rebuild"
ask 'Should I simplify by skipping failing tests? Options: 1) refine mocks 2) skip faulty tests using it.skip/describe.skip'
grep -q '^AUTO-ANSWERED (silence)' "$work/ask.log" && t "resolver: skipping failing tests is refused, however it is worded" || fail "resolver skip" "$(cat "$work/ask.log")"
ask 'The commit only modifies README.md, but the ticket requires docs/modes.md and GLOSSARY.md. Should I fail the review based on missing deliverables?'
grep -q '^AUTO-ANSWERED (deliverable)' "$work/ask.log" && t "resolver: a missing deliverable is a FAIL, the reviewer decides (D82)" || fail "resolver deliverable" "$(cat "$work/ask.log")"
ask 'Can I add an eslint-disable comment for this line?'
grep -q '^AUTO-ANSWERED (silence)' "$work/ask.log" && t "resolver: silencing a check is refused by the rule" || fail "resolver silence" "$(cat "$work/ask.log")"
ask 'Should I install vitest as a dev dependency? A) yes B) no'
grep -q '^ASKED' "$work/ask.log" && t "resolver: the same question after an auto-answer goes to the human" || fail "resolver repeat" "$(cat "$work/ask.log")"
grep -q '^Question 6 on 02-count' $m/state/open-question.md && t "a later question on a ticket suggests shrinking or resetting it" || fail "question count" "$(cat $m/state/open-question.md)"
bash scripts/factory/human.sh decide demo --stdin >/dev/null <<<'B, vitest is already there'
grep -q $'02-count\tdecide\tShould I install vitest as a dev dependency? A) yes B) no\tB, vitest' $m/decisions.tsv \
  && t "decide reads only the question, not the hint" || fail "decide question" "$(tail -1 $m/decisions.tsv)"
printf 'Keep the old count format? A) yes B) no\n' > "$work/q"
bash scripts/factory/human.sh ask demo 01-hello --stdin < "$work/q" >/dev/null; bash scripts/factory/human.sh decide demo --stdin >/dev/null <<<'A'
bash scripts/factory/human.sh ask demo 02-count --stdin < "$work/q" > "$work/ask.log"
grep -q '^AUTO-ANSWERED (earlier): A (the human' "$work/ask.log" && t "resolver: a question the human already answered gets that answer" || fail "resolver earlier" "$(cat "$work/ask.log")"
bash scripts/factory/workflow.sh build-wave demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"agent": "factory-worker-heavy"' "$wf" && t "a Size: L ticket goes straight to the heavy worker" || fail "size routing" "$(cat "$wf")"
printf 'diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml\nnew file mode 100644\n--- /dev/null\n+++ b/.github/workflows/ci.yml\n@@ -0,0 +1 @@\n+on: push\n' > "$work/evil.patch"
if bash scripts/factory/integrate.sh demo 02-count "$work/evil.patch" >"$work/int.log" 2>&1; then fail "a patch touching CI must be blocked"; fi
[ "$(bash -c '. scripts/factory/lib.sh; verdict_field .scratch/demo/verdicts/02-count-code.md Brief')" = patch-guard ] && [ ! -e .github/workflows/ci.yml ] \
  && t "patch guard blocks a worker patch touching CI (recorded as a round)" || fail "patch guard" "$(cat "$work/int.log")"
echo 'export const count = (n) => n;' > src/tools/count.js
git add -N src/tools/count.js; git diff -- src > "$work/02.patch"; git rm -q --cached src/tools/count.js; rm src/tools/count.js
bash scripts/factory/integrate.sh demo 02-count "$work/02.patch" >/dev/null
c2="$(cat $m/state/02-count.integrated)"
# The same patch again: its change is already in the branch.
head="$(git rev-parse HEAD)"; rc=0; bash scripts/factory/integrate.sh demo 02-count "$work/02.patch" >"$work/int.log" 2>&1 || rc=$?
[ "$rc" = 3 ] && grep -q 'already in this branch' "$work/int.log" && [ "$(git rev-parse HEAD)" = "$head" ] \
  && [ "$(cat $m/state/02-count.integrated)" = "$c2" ] && git diff --cached --quiet \
  && t "a patch already in the branch is reported as such, nothing committed or recorded" || fail "already integrated" "rc=$rc $(cat "$work/int.log")"
# D80: a patch that conflicts with a ticket integrated meanwhile leaves no conflicted tree.
echo 'export const count = (n) => n + 1;' > src/tools/count.js; git diff --full-index -- src/tools/count.js > "$work/02b.patch"; git checkout -q -- src/tools/count.js
echo 'export const count = (n) => n * 2;' > src/tools/count.js; git commit -qam "test: another ticket changed the same line"
pre="$(git rev-parse HEAD)"
if bash scripts/factory/integrate.sh demo 02-count "$work/02b.patch" >"$work/int.log" 2>&1; then fail "a conflicting patch must fail"; fi
grep -q 'conflicts with the current code' "$work/int.log" && [ -z "$(git status --porcelain -- src)" ] && [ -z "$(git diff --name-only --diff-filter=U)" ] \
  && grep -q 'n \* 2' src/tools/count.js && grep -q 'conflicts with code integrated' $m/verdicts/02-count-code.md \
  && t "a conflicting 3-way apply restores the tree and records a failed round (D80)" || fail "conflict" "$(cat "$work/int.log"; git status --short)"
# D84: a round that fails exactly like the one before escalates at once.
printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD="echo \\"FAIL tests/count.test.js > counts 12ms\\"; exit 1"\n' > .factory/commands.env; git commit -qam "test: a red suite"
echo 'export const count = (n) => n - 1;' > src/tools/count.js; git diff -- src > "$work/02c.patch"; git checkout -q -- src
bash scripts/factory/integrate.sh demo 02-count "$work/02c.patch" >/dev/null 2>&1 || true
[ ! -f $m/state/02-count.stuck ] && bash scripts/factory/integrate.sh demo 02-count "$work/02c.patch" >/dev/null 2>&1 || true
[ -f $m/state/02-count.stuck ] && grep -q 'No progress' $m/verdicts/02-count-code.md \
  && bash scripts/factory/next.sh demo | grep -q '02-count .*ESCALATE' \
  && t "two rounds failing the same way escalate without a third (D84)" || fail "stuck" "$(ls $m/state; bash scripts/factory/next.sh demo | head -12)"
git reset -q --hard "$head"
cat > $m/verdicts/02-count-code.md <<V
# Verdict: 02-count
**Result:** PASS
**Commit:** $c2
**Brief:** $(brief reviewer demo 02-count "$c2")

## Assertions
- VAL-HELLO-002: PASS — tests/count.test.js "counts two"
V
bash scripts/factory/collect.sh demo >/dev/null
expect_step validate "all tickets pass"

echo "Mission: behavior"
head="$(git rev-parse HEAD)"
cat > $m/verdicts/behavior.md <<V
# Verdict: behavior
**Result:** PASS
**Commit:** $head
**Brief:** $(brief validator demo - "$head")

## Assertions
- VAL-HELLO-001: PASS
- VAL-HELLO-002: PASS — unit tests
V
bash scripts/factory/collect.sh demo >/dev/null
expect_step unverified "PASS without evidence is unverified"
gate_fail "gate blocks unverified behavior" "unverified, not accepted: VAL-HELLO-001"
bash scripts/factory/human.sh accept-unverified demo VAL-HELLO-001 "no harness yet" >/dev/null
expect_step health "accepted by a human, code health next (G5)"

echo "Code health (G5)"
bash scripts/factory/health.sh check demo >"$work/health.log" 2>&1 && grep -q '^\*\*Result:\*\* PASS' $m/health/report.md \
  && t "health ratchet passes (no metric worse than the baseline)" || fail "health check" "$(cat "$work/health.log")"
bash scripts/factory/checkpoint.sh demo >/dev/null
expect_step steward "health report fresh, steward next"
bash scripts/factory/workflow.sh steward demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"agent": "factory-code-steward"' "$wf" && grep -q 'quality-bar.md' "$wf" && t "steward wave judges the mission diff against the quality bar" || fail "steward wave" "$(cat "$wf")"
head="$(git rev-parse HEAD)"
steward_verdict() {                       # <explained files...>
  { printf '# Verdict: health\n**Result:** PASS\n**Commit:** %s\n**Brief:** %s\n\n## Bar\n' "$head" "$(brief code-steward demo - "$head")"
    for q in QB-SAFE-01 QB-CLEAR-01 QB-TEST-01 QB-PRED-01; do echo "- $q: PASS — src/tools/*.js reviewed, tests/*.test.js"; done
    printf '\n## Explanations\n'; for f in "$@"; do printf '### %s\nWhat, how, what can go wrong.\n' "$f"; done
    printf '\n## Findings\n- none\n'; } > $m/verdicts/health.md
}
steward_verdict src/tools/hello.js
bash scripts/factory/collect.sh demo >/dev/null
gate_fail "gate blocks a steward verdict that leaves a changed file unexplained" "no explanation for: src/tools/count.js"
steward_verdict src/tools/hello.js src/tools/count.js
bash scripts/factory/collect.sh demo >/dev/null
grep -q '^\*\*Model:\*\* gw/judge-1 (configured for factory-code-steward)' $m/verdicts/health.md && t "steward verdict recorded with the configured model" || fail "steward model"
expect_step pr "G5 passed"
gate_ok "gate passes the whole mission (G1-G5)"
mkdir -p "$work/usage/run"; printf '{"model":"gw/maker-1","usage":{"input":120000,"output":3000,"cacheRead":90000,"cacheWrite":0,"cost":0,"turns":14},"durationMs":60000}' > "$work/usage/run/r1abc_factory-worker_meta.json"
FACTORY_USAGE_DIRS="$work/usage" bash scripts/factory/usage.sh demo >/dev/null; FACTORY_USAGE_DIRS="$work/usage" bash scripts/factory/usage.sh demo >/dev/null
[ "$(grep -c r1abc $m/usage.tsv)" = 1 ] && t "usage.sh records each run's tokens once (D85)" || fail "usage" "$(cat $m/usage.tsv 2>&1)"
bash scripts/factory/metrics.sh demo > "$work/metrics.md"
grep -q 'First-pass review rate | 0% (0/2)' "$work/metrics.md" && t "metrics: first pass from history (no ticket passed its first round)" || fail "metrics first pass" "$(cat "$work/metrics.md")"
grep -q '(3)' "$work/metrics.md" && grep -q 'patch guard | 1' "$work/metrics.md" && t "metrics: deterministic fails and guard blocks counted" || fail "metrics det" "$(cat "$work/metrics.md")"
grep -q 'factory-worker: gw/maker-1' "$work/metrics.md" && grep -q 'factory-worker-heavy: gw/maker-1' "$work/metrics.md" \
  && grep -q 'factory-contract-critic: gw/judge-1' "$work/metrics.md" \
  && t "metrics: models of every role, from the runs workflow.sh recorded (D77)" || fail "metrics models" "$(grep -i model "$work/metrics.md")"
grep -q 'Tokens (usage.tsv, D85) | 1 runs' "$work/metrics.md" && t "metrics: tokens from usage.tsv" || fail "metrics tokens" "$(grep -i token "$work/metrics.md")"

echo "Health ratchet"
mkdir -p src/lib
for f in one two; do printf 'export function %s(a, b) {\n  const x = a + b;\n  const y = x * 2;\n  const z = y - a;\n  const w = z / b;\n  const v = w + x;\n  return v + y + z;\n}\n' "$f" > src/lib/$f.js; done
git add -A src/lib; git commit -q -m "feat: copy-paste"
expect_step health "source change makes the health report stale"
if bash scripts/factory/health.sh check demo >"$work/health.log" 2>&1; then fail "duplication must fail the ratchet" "$(cat "$work/health.log")"; fi
grep -q 'duplicate_blocks | 0 | [1-9]' $m/health/report.md && t "ratchet fails on new duplication" || fail "ratchet dup" "$(cat $m/health/report.md)"
bash scripts/factory/checkpoint.sh demo >/dev/null
expect_step health-fix "failing health report asks for fix tickets"
bash scripts/factory/workflow.sh tickets demo fix-health >"$work/wf.log"
grep -q 'fix ticket per finding in .scratch/demo/verdicts/health.md' "$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")" && t "fix-health tickets drafted by the ticket writer" || fail "fix-health wave"
git rm -q -r src/lib; git commit -q -m "fix: remove duplication"
bash scripts/factory/human.sh approve demo tickets >/dev/null
expect_step health "fix built, health checked again"
bash scripts/factory/health.sh check demo >/dev/null && bash scripts/factory/checkpoint.sh demo >/dev/null
expect_step pr "back to the measured baseline; steward verdict still fresh"

echo "Staleness and pause"
echo '# docs' >> README.md; git commit -q -am "docs: readme"
expect_step pr "docs change keeps behavior and health verdicts fresh"
echo 'export const b = 2;' >> src/tools/a.js; git commit -q -am "feat: behavior change"
expect_step behavior-stale "behavior path change makes it stale"
bash scripts/factory/pause.sh demo "context" >/dev/null
expect_step paused "paused mission"
bash scripts/factory/pause.sh resume demo >/dev/null
expect_step behavior-stale "resume returns to the same step"

echo "Fix lane"
bash scripts/factory/fix.sh start helm-name "rename app to kebab case" --mission demo >/dev/null
sed -i.bak 's/x/y/' README.md && rm README.md.bak; mkdir -p deploy; echo 'name: bot-x' > deploy/values.yaml
git add -A; git commit -q -m "fix(deploy): kebab-case app name"
bash scripts/factory/fix.sh check helm-name >"$work/fix.log" 2>&1 && t "small non-behavior fix passes blast radius + checks" || fail "fix check" "$(cat "$work/fix.log")"
grep -q 'workflow.sh light helm-name' "$work/fix.log" && t "fix lane hands over to one light reviewer" || fail "fix next"
# D75: the fix-lane reviewer can ask, and the human answers, without a mission.
printf 'Should the chart keep the old name as an alias?\n' | bash scripts/factory/human.sh ask helm-name - --stdin >"$work/ask.log" 2>&1 \
  && grep -q 'ASKED' "$work/ask.log" && [ -f .scratch/light/helm-name/state/open-question.md ] \
  && bash scripts/factory/human.sh decide helm-name "no alias" >/dev/null 2>&1 \
  && grep -q 'no alias' .scratch/light/helm-name/decisions.tsv && [ ! -f .scratch/light/helm-name/state/open-question.md ] \
  && t "fix lane: a reviewer's question is recorded and answered without a mission spec" || fail "light ask" "$(cat "$work/ask.log")"
bash scripts/factory/human.sh approve helm-name >"$work/ask.log" 2>&1 && fail "approve must need a mission"
grep -q 'needs a mission' "$work/ask.log" && t "fix lane: contract gates still need a mission" || fail "light approve" "$(cat "$work/ask.log")"
# D76: deleting code doesn't count against the fix-lane limit.
bash scripts/factory/fix.sh start dedupe "remove duplicated lists" >/dev/null
mkdir -p docs/dup; seq 1 150 > docs/dup/list.txt; git add -A; git commit -q -m "docs: list"
bash scripts/factory/fix.sh start dedupe2 "remove duplicated lists" >/dev/null
git rm -q docs/dup/list.txt; mkdir -p docs/dup; echo 'see the generator' > docs/dup/README.md; git add -A; git commit -q -m "docs: drop the copied list"
bash scripts/factory/fix.sh check dedupe2 >"$work/fix.log" 2>&1 && grep -q 'Lines removed:\*\* 150' "$work/fix.log" \
  && t "fix lane: 150 deleted lines pass the limit, only added lines count (D76)" || fail "fix deletions" "$(cat "$work/fix.log")"
bash scripts/factory/fix.sh start tool-tweak "tweak a tool" >/dev/null
echo '// tweak' >> src/tools/a.js; git commit -q -am "fix: tweak"
if bash scripts/factory/fix.sh check tool-tweak >"$work/fix.log" 2>&1; then fail "behavior fix must be blocked" "$(cat "$work/fix.log")"; fi
grep -q 'BLOCKED' "$work/fix.log" && t "fix touching behavior paths is blocked" || fail "fix block"

echo "MR gate"
git switch -q -c light-demo "$base0"
echo 'docs: z' > deploy.txt; git add deploy.txt; git commit -q -m "chore: deploy tweak"
if bash scripts/factory/gate.sh mr "$base0" >"$work/mr.log" 2>&1; then fail "light lane without review must fail" "$(cat "$work/mr.log")"; fi
grep -q 'Lane: LIGHT' "$work/mr.log" && t "MR without behavior change is light lane, needs a review" || fail "light lane" "$(cat "$work/mr.log")"
base="$base0"; head="$(git rev-parse HEAD)"
mkdir -p .scratch/light/deploy/verdicts
cat > .scratch/light/deploy/verdicts/code.md <<V
# Verdict: deploy
**Result:** PASS
**Commit:** $head
**Brief:** $(bash scripts/factory/brief.sh light-reviewer deploy - "$head" "$base" | sed -n 's/^brief-id: //p')

## Issues
- [suggestion] none
V
bash scripts/factory/collect.sh --light deploy >/dev/null
bash scripts/factory/gate.sh mr "$base0" >"$work/mr.log" 2>&1 && t "light lane passes with a recorded review" || fail "light pass" "$(cat "$work/mr.log")"
echo 'export const c = 3;' >> src/tools/a.js; git commit -q -am "feat: sneak"
if bash scripts/factory/gate.sh mr "$base0" >"$work/mr.log" 2>&1; then fail "behavior without mission must fail"; fi
grep -q 'no mission is part of this MR' "$work/mr.log" && t "behavior change without a mission is blocked" || fail "full lane" "$(cat "$work/mr.log")"
git switch -q -

bash scripts/factory/fix.sh start lint-hush "silence a warning" >/dev/null
printf '// eslint-disable-next-line\n' >> README.md; git commit -q -am "fix: hush"
if bash scripts/factory/fix.sh check lint-hush >"$work/fix.log" 2>&1; then fail "silenced check must be blocked in the fix lane"; fi
grep -q 'BLOCKED silence' "$work/fix.log" && t "patch guard applies to human fixes too (silenced check)" || fail "fix guard" "$(cat "$work/fix.log")"
git revert --no-edit HEAD >/dev/null

echo "Lint baseline (D62) and reset (D63)"
# Fake linter: "BAD" in a tracked .js file is an error, reported with an absolute path.
printf '%s\n' 'st=0' \
  'while IFS= read -r f; do n=0' \
  '  while IFS= read -r l; do n=$((n + 1)); case "$l" in *BAD*) echo "$PWD/$f:$n:1: error Unexpected BAD [no-bad]"; st=1 ;; esac; done < "$f"' \
  "done < <(git ls-files -- '*.js'); echo '1 problem'; exit \$st" > "$work/lint.sh"
echo '// BAD legacy' > src/legacy.js
printf 'FACTORY_LINT_CMD="bash %s"\nFACTORY_TEST_CMD="true"\n' "'$work/lint.sh'" > .factory/commands.env
git add -A; git commit -qm "test: legacy lint error"
keys="$(printf '%s\n' "$PWD/src/x.ts" '  3:5  error  Unexpected any  @typescript-eslint/no-explicit-any' '  9:1  warning  Unused  no-unused-vars' '' '✖ 2 problems (1 error, 1 warning)' "src/y.ts(12,7): error TS2322: Type 'a' is not assignable." \
  | node scripts/factory/lint-keys.mjs "$PWD" | paste -sd'|' -)"
[ "$keys" = "src/x.ts: Unexpected any @typescript-eslint/no-explicit-any|src/y.ts: error TS2322: Type 'a' is not assignable." ] \
  && t "lint keys: eslint stylish and tsc output, warnings and summaries ignored" || fail "lint keys" "$keys"
ok_patch() { printf 'diff --git a/tests/%s b/tests/%s\nnew file mode 100644\n--- /dev/null\n+++ b/tests/%s\n@@ -0,0 +1 @@\n+%s\n' "$1" "$1" "$1" "$2" > "$work/$1.patch"; }
ok_patch ok.test.js 'it("ok", () => {});'
if bash scripts/factory/integrate.sh maint 02-tests "$work/ok.test.js.patch" >"$work/int.log" 2>&1; then fail "without a baseline, a legacy lint error fails" "$(cat "$work/int.log")"; fi
grep -q 'no .factory/lint-baseline.txt' .scratch/maint/logs/02-tests-integrate.log && t "no lint baseline: legacy errors fail, and the log says why" || fail "no baseline" "$(cat .scratch/maint/logs/02-tests-integrate.log)"
bash scripts/factory/health.sh baseline >"$work/hb.log" 2>&1 && [ "$(cat .factory/lint-baseline.txt)" = 'src/legacy.js: error Unexpected BAD [no-bad]' ] \
  && t "health.sh baseline records the lint errors (relative path, no line numbers)" || fail "lint baseline" "$(cat "$work/hb.log" .factory/lint-baseline.txt)"
printf '// header\n// BAD legacy\n' > src/legacy.js; git add -A; git commit -qm "test: baseline + shifted legacy line"
bash scripts/factory/integrate.sh maint 02-tests "$work/ok.test.js.patch" >"$work/int.log" 2>&1 && [ -f .scratch/maint/state/02-tests.integrated ] \
  && grep -q 'only errors already in' .scratch/maint/logs/02-tests-integrate.log \
  && t "only baseline errors (on a moved line): integration passes" || fail "baseline pass" "$(cat "$work/int.log" .scratch/maint/logs/02-tests-integrate.log)"
ok_patch bad.test.js '// BAD new'
if bash scripts/factory/integrate.sh maint 03-more "$work/bad.test.js.patch" >"$work/int.log" 2>&1; then fail "a new lint error must fail" "$(cat "$work/int.log")"; fi
grep -q 'New lint errors (fix them, never silence them): tests/bad.test.js: error Unexpected BAD' .scratch/maint/verdicts/03-more-code.md && [ ! -e tests/bad.test.js ] \
  && t "a new lint error fails integration; the verdict names it" || fail "new lint" "$(cat .scratch/maint/verdicts/03-more-code.md)"
bash scripts/factory/health.sh check maint >"$work/health.log" 2>&1 || true; grep -q 'lint_errors_new | 0 | 0 | same' .scratch/maint/health/report.md \
  && t "health check: no new lint error against the baseline" || fail "health lint row" "$(cat "$work/health.log")"
bash scripts/factory/fix.sh start lint-legacy "touch legacy" >/dev/null
echo '// tweak' >> README.md; git commit -qam "fix: readme tweak"
bash scripts/factory/fix.sh check lint-legacy >"$work/fix.log" 2>&1 && grep -q '✓ lint' "$work/fix.log" && t "fix lane: legacy lint errors don't fail a human fix" || fail "fix lint" "$(cat "$work/fix.log")"
bash scripts/factory/doctor.sh --quick > "$work/pre.log" 2>&1 || true
grep -q 'lint baseline present' "$work/pre.log" && t "pre-flight reports the lint baseline" || fail "doctor lint baseline" "$(cat "$work/pre.log")"

[ -f .scratch/maint/verdicts/03-more-code.r1.md ] && bash scripts/factory/reset-ticket.sh maint 03-more "rebuild after lint fix" >"$work/reset.log" \
  && [ -z "$(ls .scratch/maint/verdicts/03-more-code* 2>/dev/null)" ] && [ -z "$(git status --porcelain -- .scratch)" ] \
  && [ "$(git log -1 --format=%s)" = 'chore(maint): reset 03-more' ] && grep -q $'03-more\treset\t.*rebuild after lint fix' .scratch/maint/decisions.tsv \
  && [ -z "$(bash -c '. scripts/factory/lib.sh; verdict_round .scratch/maint/verdicts/03-more-code.md')" ] \
  && t "reset-ticket: verdict and round copies gone, logged, one commit" || fail "reset 03" "$(cat "$work/reset.log"; ls .scratch/maint/verdicts)"
bash scripts/factory/reset-ticket.sh maint 02-tests >/dev/null && [ ! -e .scratch/maint/state/02-tests.integrated ] \
  && bash -c '. scripts/factory/lib.sh; compute_ticket_state maint; [[ " ${T_BUILD[*]} " == *" 02-tests "* ]]' \
  && t "reset-ticket: an integrated ticket loses its marker and goes back to build" || fail "reset 02"
[ "$(bash scripts/factory/reset-ticket.sh maint 02-tests)" = "Nothing to reset for 02-tests." ] && t "reset-ticket: nothing to reset is a no-op" || fail "reset noop"
if bash scripts/factory/reset-ticket.sh maint 99-nope >/dev/null 2>&1; then fail "unknown ticket must be refused"; fi
t "reset-ticket: an unknown ticket is refused"
git rm -q src/legacy.js .factory/lint-baseline.txt; printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD="test -f src/tools/a.js"\n' > .factory/commands.env
git add -A; git commit -qm "test: back to the plain commands"

echo "Pre-flight"
bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1 && t "pre-flight OK on a configured repo" || fail "preflight" "$(cat "$work/pre.log")"
echo dirty >> src/tools/a.js
if bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1; then fail "dirty tree must fail pre-flight"; fi
t "pre-flight fails on a dirty tree"
git checkout -q -- src/tools/a.js
printf '.scratch/\n' >> .gitignore
if bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1; then fail "ignored .scratch must fail pre-flight"; fi
grep -q "git-ignored" "$work/pre.log" && t "pre-flight fails when .scratch/ is git-ignored" || fail "gitignore check" "$(cat "$work/pre.log")"
git checkout -q -- .gitignore

# Model probe against a fake gateway reproducing mission 2 (D59).
cat > "$work/gw.mjs" <<'EOF'
import http from "node:http";
http.createServer((req, res) => { let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => {
  if (req.url.endsWith("/models")) { res.writeHead(200); return res.end(JSON.stringify({ data: (process.env.SERVED || "").split(",").map((id) => ({ id })) })); }
  if (req.method !== "POST") { res.writeHead(200); return res.end("{}"); }
  if (JSON.parse(b).model === process.env.PICKY) { res.writeHead(400); return res.end('{"message":"Unexpected role user after role tool"}'); }
  res.writeHead(200); res.end("{}"); }); }).listen(Number(process.env.PORT), "127.0.0.1");
EOF
port=$((20000 + RANDOM % 20000)); ids="$(sed -n 's/^model: [^/]*\///p' .pi/agents/factory/*.md | sort -u | paste -sd, -)"
SERVED="$ids" PICKY="$(cut -d, -f1 <<<"$ids")" PORT=$port node "$work/gw.mjs" & gw=$!; sleep 1
export FACTORY_GATEWAY_URL="http://127.0.0.1:$port/v1" NO_PROXY="127.0.0.1,${NO_PROXY:-}" no_proxy="127.0.0.1,${no_proxy:-}"
if node scripts/factory/models-probe.mjs --stamp >"$work/probe.log" 2>&1; then fail "probe must reject a model that refuses tool turns"; fi
grep -q "rejects a user turn after a tool result" "$work/probe.log" && [ ! -f .factory/models-probe.ok ] \
  && t "probe catches a model that rejects tool turns, no stamp" || fail "probe tool turn" "$(cat "$work/probe.log")"
kill $gw; wait $gw 2>/dev/null || true
SERVED="$ids" PICKY=none PORT=$port node "$work/gw.mjs" & gw=$!; sleep 1
printf 'FACTORY_GATEWAY_URL="%s"\n' "$FACTORY_GATEWAY_URL" >> .factory/commands.env; git commit -qam "test: gateway"
if bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1; then fail "unprobed models must fail pre-flight"; fi
grep -q "models changed since the last probe" "$work/pre.log" && t "pre-flight requires a probe after a model change" || fail "probe stamp" "$(cat "$work/pre.log")"
node scripts/factory/models-probe.mjs --stamp >"$work/probe.log" 2>&1 && git add .factory/models-probe.ok && git commit -qm "test: probe" \
  && bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1 && t "probed models pass pre-flight" || fail "probe ok" "$(cat "$work/probe.log" "$work/pre.log")"
kill $gw; wait $gw 2>/dev/null || true; unset FACTORY_GATEWAY_URL

# D79: two gateways, as in mission 2's last day. Pi's models.json maps each
# provider to its own URL and key; the worker's provider doesn't serve its model.
maker="$(sed -n 's/^model: gw\///p' .pi/agents/factory/factory-worker.md)"; judge="$(sed -n 's/^model: gw\///p' .pi/agents/factory/factory-reviewer.md)"
for a in .pi/agents/factory/*.md; do sed -i.bak "s|^model: gw/$maker|model: makers/$maker|; s|^model: gw/$judge|model: judges/$judge|" "$a" && rm -f "$a.bak"; done
node -e '
const fs=require("fs"); const f=".factory/model-families.json"; const j=JSON.parse(fs.readFileSync(f,"utf8"));
j.families.unshift({match:"makers/*",family:"maker"},{match:"judges/*",family:"judge"}); fs.writeFileSync(f, JSON.stringify(j,null,2));'
p1=$((port + 1)); p2=$((port + 2)); mkdir -p "$PI_CODING_AGENT_DIR"
printf '{"providers":{"makers":{"baseUrl":"http://127.0.0.1:%s/v1","api":"openai-completions","apiKey":"MAKERS_KEY","models":[]},"judges":{"baseUrl":"http://127.0.0.1:%s/v1","api":"openai-completions","apiKey":"literal-key","models":[]}}}' "$p1" "$p2" > "$PI_CODING_AGENT_DIR/models.json"
SERVED="other-model" PICKY=none PORT=$p1 node "$work/gw.mjs" & g1=$!
SERVED="$judge" PICKY=none PORT=$p2 node "$work/gw.mjs" & g2=$!; sleep 1
if MAKERS_KEY=env-key-4711 node scripts/factory/models-probe.mjs >"$work/probe.log" 2>&1; then fail "probe must catch a model its provider doesn't serve"; fi
grep -q "factory-worker: makers/$maker is not served to this key on makers" "$work/probe.log" && grep -q "factory-reviewer: judges/$judge served" "$work/probe.log" \
  && t "probe: each agent on its own provider from Pi's models.json; the 403 case is caught before a wave (D79)" || fail "two gateways" "$(cat "$work/probe.log")"
kill $g1; wait $g1 2>/dev/null || true
SERVED="$maker" PICKY=none PORT=$p1 node "$work/gw.mjs" & g1=$!; sleep 1
MAKERS_KEY=env-key-4711 node scripts/factory/models-probe.mjs >"$work/probe.log" 2>&1 && grep -q 'PROBE: OK' "$work/probe.log" && ! grep -qE 'literal-key|env-key-4711' "$work/probe.log" \
  && t "probe: two gateways pass, keys never printed" || fail "two gateways ok" "$(cat "$work/probe.log")"
kill $g1 $g2; wait $g1 $g2 2>/dev/null || true
git checkout -q -- .pi .factory; rm -f "$PI_CODING_AGENT_DIR/models.json"

# D90: the cockpit's snapshot comes from the mission's files, nothing else.
bash scripts/factory/status.sh demo --json > "$work/status.json" || fail "status.sh" "$(cat "$work/status.json")"
STEP_NOW="$(FACTORY_NOTIFY=0 bash scripts/factory/next.sh demo | sed -n 's/^STEP: //p')" node -e '
const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const m = s.missions[0];
const ok = m.name === "demo" && m.step === process.env.STEP_NOW && m.counts.total === 2 && m.counts.pass === 2
  && m.tickets[1].blockedBy.join() === "01" && m.tickets[1].assertions[0].id === "VAL-HELLO-002" && /Given two greetings/.test(m.tickets[1].assertions[0].given)
  && m.interventions.target === 5 && m.interventions.human >= 2 && m.contract.total === 2
  && m.log.some((e) => e.kind === "integrated" && e.ticket === "01-hello") && m.log.some((e) => e.kind === "verdict" && e.ticket === "02-count")
  && m.log.some((e) => e.kind === "decision") && !m.log.some((e) => /state$/.test(e.text));
process.exit(ok ? 0 : 1);' "$work/status.json" && t "status.sh --json: the step next.sh gives, tickets with preconditions and expected behavior, interventions, a log of events without checkpoints (D90)" || fail "status json" "$(head -c 3000 "$work/status.json")"
printf '**Ticket:** 02-count\n\nShould the count start at zero?\n' > $m/state/open-question.md
bash scripts/factory/status.sh --all --json > "$work/all.json"
node -e '
const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const m = s.missions.find((x) => x.name === "demo");
process.exit(m && m.step === "decide" && m.needs[0].kind === "decide" && m.needs.some((n) => /start at zero/.test(n.text) || /factory-decide/.test(n.text)) ? 0 : 1);' "$work/all.json" \
  && t "status.sh --all: every mission, an open question shows as needs-you" || fail "status all" "$(head -c 2000 "$work/all.json")"
rm -f $m/state/open-question.md
bash scripts/factory/cockpit.sh --once "$work/cockpit" >/dev/null && [ -s "$work/cockpit/index.html" ] && grep -q '"missions"' "$work/cockpit/state.json" \
  && [ -z "$(git status --porcelain -- .scratch)" ] && t "cockpit.sh --once writes the page and its snapshot outside the repo, read-only" || fail "cockpit once" "$(ls "$work/cockpit"; git status --porcelain)"

# D86: one command opens the MR from /pr's body.
out="$(FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo --dry-run 2>&1)" && fail "mr.sh must refuse without a PR body"
echo "$out" | grep -q 'run /pr first' && t "mr.sh refuses without a PR body" || fail "mr no body" "$out"
printf '# test(demo): characterize the hello tools\n\n## Summary\n\nTwo tools pinned.\n' > $m/pr.md
out="$(FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo --dry-run 2>&1)"
echo "$out" | grep -q "→ production" && echo "$out" | grep -q 'title: test(demo): characterize the hello tools' \
  && t "mr.sh: title from the body's heading, target from FACTORY_MR_TARGET" || fail "mr dry" "$out"
cur="$(git rev-parse --abbrev-ref HEAD)"
out="$(FACTORY_MR_TARGET=production FACTORY_MR_BLOCKED_BRANCHES="other/* ${cur%%/*}*" bash scripts/factory/mr.sh demo --dry-run 2>&1)" && fail "mr.sh must refuse a blocked branch"
echo "$out" | grep -q 'FACTORY_MR_BLOCKED_BRANCHES' && t "mr.sh refuses a branch that deploys (FACTORY_MR_BLOCKED_BRANCHES)" || fail "mr blocked" "$out"
out="$(FACTORY_MR_TARGET="$cur" bash scripts/factory/mr.sh demo --dry-run 2>&1)" && fail "mr.sh must refuse the target itself"
printf '# chore: x [skip ci]\n' > "$work/skip.md"; cp $m/pr.md "$work/pr.keep"; cp "$work/skip.md" $m/pr.md
out="$(FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo --dry-run 2>&1)" && fail "mr.sh must refuse a title that skips CI"
cp "$work/pr.keep" $m/pr.md; t "mr.sh refuses the target branch itself and a title that skips CI"
git init -q --bare "$work/origin.git"; git remote remove origin 2>/dev/null || true; git remote add origin "$work/origin.git"
mkdir -p "$work/bin"; cat > "$work/bin/glab" <<'GLAB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "mr list") echo '[]' ;;
  "mr create") printf '%s\n' "$@" > "$GLAB_LOG"; echo "https://gitlab.example/g/p/-/merge_requests/7" ;;
esac
GLAB
chmod +x "$work/bin/glab"
GLAB_LOG="$work/glab.log" PATH="$work/bin:$PATH" FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo >"$work/mr.log" 2>&1 || fail "mr glab" "$(cat "$work/mr.log")"
git ls-remote --heads "$work/origin.git" "$cur" | grep -q . && grep -qx 'production' "$work/glab.log" && grep -qx 'test(demo): characterize the hello tools' "$work/glab.log" \
  && grep -q '^## Summary' "$work/glab.log" && ! grep -q '^# test' "$work/glab.log" && grep -q 'merge_requests/7' $m/mr.url \
  && t "mr.sh pushes the branch and opens the MR with glab; heading becomes the title, the rest the description (D86)" || fail "mr glab create" "$(cat "$work/mr.log" "$work/glab.log")"
git remote remove origin; rm -f $m/pr.md $m/mr.url

if [ -n "${mono:-}" ]; then
  [ "$(cat "$mono/projects/other/keep.js")" = keep ] && [ -z "$(git -C "$mono" log --format=%H -- projects/other README.md | awk 'NR > 1')" ] \
    && t "monorepo: a whole mission never touched the sibling project or the root" || fail "monorepo leak" "$(git -C "$mono" log --stat -- projects/other README.md)"
fi

echo; echo "ALL $pass CHECKS PASSED"
