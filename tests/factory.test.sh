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
brief_out="$(bash scripts/factory/brief.sh worker probe 01 HEAD)"   # captured: grep -q closing the pipe early made this flaky
grep -q '^Read: docs/agents/factory.md' <<<"$brief_out" && ! grep -q 'AGENTS.md' <<<"$brief_out" \
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
# Capture from a place without model scope or families (the factory folder, a
# mirror) keeps the profile's, and keeps agents only the profile has.
cp "$PI_FACTORY_MODELS" "$work/profile.keep"
node -e 'const f=require("fs"),p=process.argv[1],j=JSON.parse(f.readFileSync(p));j.agents["factory-extra"]={model:"gw/judge-9"};f.writeFileSync(p,JSON.stringify(j))' "$PI_FACTORY_MODELS"
mv .factory/model-families.json "$work/fam.keep"; cp .pi/settings.json "$work/set.keep"
node -e 'const f=require("fs"),s=".pi/settings.json",k=JSON.parse(f.readFileSync(s));delete k.subagents.modelScope;f.writeFileSync(s,JSON.stringify(k))'
cap="$(node scripts/factory/models-profile.mjs capture 2>&1)"
mv "$work/fam.keep" .factory/model-families.json; cp "$work/set.keep" .pi/settings.json
node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1]));process.exit(j.allow.includes("gw/*")&&j.families.some(f=>f.family==="judges")&&j.agents["factory-extra"]&&j.agents["factory-reviewer"]?0:1)' "$PI_FACTORY_MODELS" \
  && grep -q 'kept from the profile: model scope; families; agents factory-extra' <<<"$cap" && [ -f "$PI_FACTORY_MODELS.bak" ] \
  && t "capture keeps the profile's model scope, families and agents it can't see; a .bak first" || fail "capture merge" "$cap"$'\n'"$(cat "$PI_FACTORY_MODELS")"
cp "$work/profile.keep" "$PI_FACTORY_MODELS"
rc=0; out="$(cd "$root" && node scripts/factory/models-lint.mjs 2>&1)" || rc=$?
[ "$rc" = 2 ] && grep -q "the factory's own folder, not a project" <<<"$out" \
  && t "models-lint in the factory's own folder says so instead of false failures" || fail "lint in factory folder" "rc=$rc $out"
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
# D93: a refactor changes the code, never the tests that pin its behavior.
mkdir -p .scratch/refac
printf '# Refac\n**Intent:** refactor\n\n## Validation contract\n' > .scratch/refac/spec.md
out="$(bash scripts/factory/next.sh refac)"
grep -q '^STEP: blocked' <<<"$out" && grep -q 'list them under "## Frozen tests"' <<<"$out" && t "a refactor without frozen tests does not start (D93)" || fail "refactor needs tests" "$out"
printf '# Refac\n**Intent:** refactor\n\n## Frozen tests\n- `tests/missing/`\n\n## Validation contract\n' > .scratch/refac/spec.md
out="$(bash scripts/factory/next.sh refac)"
grep -q 'names what doesn.t exist here: tests/missing/' <<<"$out" && t "a refactor whose frozen tests are not on this branch does not start" || fail "refactor tests exist" "$out"
mkdir -p tests/pinned; echo 'it("pins", () => {});' > tests/pinned/a.test.js
printf '# Refac\n**Intent:** refactor\n\n## Frozen tests\n- `tests/pinned/`\n\n## Validation contract\n' > .scratch/refac/spec.md
printf 'diff --git a/tests/pinned/a.test.js b/tests/pinned/a.test.js\n--- a/tests/pinned/a.test.js\n+++ b/tests/pinned/a.test.js\n@@ -1 +1 @@\n-it("pins", () => {});\n+it.todo("pins");\n' > "$work/rf.patch"
if bash scripts/factory/patch-guard.sh "$work/rf.patch" --mission refac >"$work/pg.log"; then fail "refactor must refuse a change to a frozen test"; fi
grep -q '^BLOCKED frozen-tests: tests/pinned/a.test.js' "$work/pg.log" && t "refactor: a frozen test can't change, though it is a test file (D93)" || fail "frozen tests" "$(cat "$work/pg.log")"
printf '%b' "$src_patch" > "$work/rf.patch"
bash scripts/factory/patch-guard.sh "$work/rf.patch" --mission refac >/dev/null && t "refactor: the code itself is free to change" || fail "refactor src" "$(bash scripts/factory/patch-guard.sh "$work/rf.patch" --mission refac)"
grep -qF 'Frozen tests (not a line of them may change, D93): `tests/pinned/`' <<<"$(bash scripts/factory/brief.sh worker refac 01)" && t "the worker brief names the frozen tests" || fail "brief frozen tests"
rm -rf .scratch/refac tests/pinned
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
**Reviewer:** jdoe

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
# D101: an approval line typed by hand (or by an agent) has no decisions.tsv row: it approves nothing.
cp $m/spec.md "$work/spec.bak"; printf '\n**Contract approved:** %s\n' "$(date +%F)" >> $m/spec.md
out="$(bash scripts/factory/next.sh demo 2>&1)"
gate_out="$(bash scripts/factory/gate.sh mission demo 2>&1 || true)"
[ "$(head -1 <<<"$out")" = "STEP: approve" ] && grep -q 'no /factory-approve record in decisions.tsv' <<<"$out" \
  && grep -q 'G1: the approval line has no /factory-approve record' <<<"$gate_out" \
  && ! bash scripts/factory/workflow.sh design demo >/dev/null 2>&1 \
  && t "a hand-written approval line counts nowhere: next.sh, gate.sh and workflow.sh agree (D101)" || fail "self-approval" "$out$gate_out"
cp "$work/spec.bak" $m/spec.md
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
FACTORY_APPROVER="Test Human" bash scripts/factory/human.sh approve demo >/dev/null
grep -qE '^\*\*Contract approved:\*\* [0-9-]+ — by Test Human' $m/spec.md && t "the approval line records who approved (D95)" || fail "approver" "$(grep 'Contract approved' $m/spec.md)"
# D94: a feature mission gets a program design after G1, approved before tickets.
expect_step design "feature mission, G1 approved, no design"
bash scripts/factory/workflow.sh design demo >"$work/wf.log"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"agent": "factory-designer"' "$wf" && grep -q 'design-format.md' "$wf" && grep -q '.scratch/demo/design.md' "$wf" \
  && t "the design wave runs the designer on the approved contract" || fail "design wave" "$(cat "$wf")"
printf '# Design: demo\n\n## Call stacks\n```diff\n+greet  # VAL-HELLO-001\n```\n\n## Slices\n1. hello end to end — VAL-HELLO-001\n' > $m/design.md
git add -A; git commit -qm "test: design draft"
out="$(bash scripts/factory/next.sh demo)"
grep -q '^STEP: approve-design' <<<"$out" && grep -q 'and jdoe, who will review the MR' <<<"$out" \
  && t "an unapproved design waits for the human and the MR's reviewer (G1b)" || fail "approve-design" "$out"
cp $m/design.md "$work/design.bak"; printf '**Design approved:** %s\n' "$(date +%F)" | cat - "$work/design.bak" > $m/design.md
out="$(bash scripts/factory/next.sh demo)"
grep -q '^STEP: approve-design' <<<"$out" && grep -q 'no /factory-approve record' <<<"$out" \
  && t "a hand-written design approval waits for /factory-approve (D101)" || fail "design self-approval" "$out"
cp "$work/design.bak" $m/design.md
FACTORY_APPROVER="Test Human" bash scripts/factory/human.sh approve demo design >/dev/null
sed -n 2p $m/design.md | grep -qE '^\*\*Design approved:\*\* [0-9-]+ — by Test Human' && grep -q $'\tapprove-design\t' $m/decisions.tsv \
  && [ -z "$(git status --porcelain -- .scratch)" ] && t "/factory-approve <f> design writes the line under the title, logs it, checkpoints" || fail "approve design" "$(head -3 $m/design.md)"
expect_step tickets "approved, no tickets"
grep -q 'design.md if it exists (approved' <<<"$(bash scripts/factory/brief.sh ticket-writer demo all)" && grep -q 'Write vertical slices' <<<"$(bash scripts/factory/brief.sh ticket-writer demo all)" \
  && grep -q 'design.md exists, it is approved' <<<"$(bash scripts/factory/brief.sh reviewer demo 01-hello)" \
  && t "ticket writer follows the design in vertical slices; the reviewer checks commits against it (D94, D95)" || fail "design briefs"
dn() { bash -c '. scripts/factory/lib.sh; f="$(mktemp)"; printf "%b" "$1" > "$f"; design_needed "$f" && echo yes || echo no' _ "$1"; }
[ "$(dn '**Intent:** feature\n')" = yes ] && [ "$(dn '**Intent:** refactor\n')" = yes ] && [ "$(dn '**Intent:** maintenance\n')" = no ] \
  && [ "$(dn '**Intent:** bugfix\n')" = no ] && [ "$(dn '**Intent:** bugfix\n**Design:** yes\n')" = yes ] && [ "$(dn '**Intent:** feature\n**Design:** no\n')" = no ] \
  && t "design: feature and refactor by default, maintenance and bugfix skip it, **Design:** overrides" || fail "design_needed"
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
mkdir -p "$work/tmp/other-run"; echo 'diff --git a/x b/x' > "$work/tmp/other-run/01-hello.patch"; echo '{"cwd":"/elsewhere/repo"}' > "$work/tmp/other-run/meta.json"
[ "$(TMPDIR="$work/tmp" bash scripts/factory/locate-patch.sh demo 01-hello 2>/dev/null)" = "$draft" ] \
  && t "locate-patch ignores a temp patch from another checkout with the same mission name" || fail "foreign patch" "$(TMPDIR="$work/tmp" bash scripts/factory/locate-patch.sh demo 01-hello 2>&1)"
printf '{"cwd":"%s"}' "$(git rev-parse --show-toplevel)" > "$work/tmp/other-run/meta.json"
[ "$(TMPDIR="$work/tmp" bash scripts/factory/locate-patch.sh demo 01-hello 2>/dev/null)" = "$work/tmp/other-run/01-hello.patch" ] \
  && t "locate-patch takes a temp patch whose run names this checkout" || fail "own patch" "$(TMPDIR="$work/tmp" bash scripts/factory/locate-patch.sh demo 01-hello 2>&1)"
rm -rf "$work/tmp"
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
[ "$(git log -1 --format='%an <%ae>' "$c1")" = "pi-factory <pi-factory@localhost>" ] && [ "$(git log -1 --format=%cn "$c1")" = "$GIT_COMMITTER_NAME" ] \
  && [ "$(git log -1 --skip=0 --format=%an HEAD)" = pi-factory ] \
  && t "factory commits are authored by pi-factory and committed by the human (D100)" || fail "factory identity" "$(git log -3 --format='%an / %cn: %s')"
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
  && grep -q '02-count .*ESCALATE' <<<"$(bash scripts/factory/next.sh demo)" \
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
hand0="$(sed -n 's/^| Hand commits in the mission[^|]*| \([0-9]*\) |$/\1/p' "$work/metrics.md")"
echo "// hand repair" >> src/tools/hello.js; git commit -qam "fix: hand repair"
bash scripts/factory/metrics.sh demo > "$work/metrics2.md"; git revert --no-edit HEAD >/dev/null
hand1="$(sed -n 's/^| Hand commits in the mission[^|]*| \([0-9]*\) |$/\1/p' "$work/metrics2.md")"
[ -n "$hand0" ] && [ "$hand1" = $((hand0 + 1)) ] && t "metrics: a hand commit counts as an intervention; script commits carry Factory-Script (D89)" || fail "hand commits" "$hand0 → $hand1"
# D97: the run archive, scoring, metrics across missions.
bid="$(bash -c '. scripts/factory/lib.sh; verdict_field "$1" Brief' _ $m/verdicts/01-hello-code.md)"
printf 'Role: factory-worker. Mission demo, ticket 01-hello.\n\nbrief-id: %s\n' "$bid" > "$work/usage/run/r1abc_factory-worker_input.md"
printf 'Done. REPRO: npm test\n' > "$work/usage/run/r1abc_factory-worker_output.md"
printf '{"type":"tool","name":"bash","args":"npm test"}\n{"type":"text","text":"token = \\"glpat-abcdefghij0123456789\\""}\n' > "$work/usage/run/r1abc_factory-worker_transcript.jsonl"
FACTORY_USAGE_DIRS="$work/usage" bash scripts/factory/archive.sh collect demo >/dev/null
arch="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/archive/demo/r1abc_factory-worker"
node -e 'const r=require(process.argv[1]+"/run.json"); process.exit(r.agent==="factory-worker" && r.model==="gw/maker-1" && r.ticket==="01-hello" && r.briefId===process.argv[2] && r.outcome.result && r.usage.turns===14 ? 0 : 1)' "$arch" "$bid" \
  && grep -q 'npm test' "$arch/transcript.jsonl" && ! grep -q 'glpat-' "$arch/transcript.jsonl" && grep -q 'REDACTED' "$arch/transcript.jsonl" \
  && [ -z "$(git status --porcelain -- "$m" | grep -v usage.tsv)" ] \
  && t "archive: brief, transcript (secrets redacted), usage and outcome kept outside the repo (D97)" || fail "archive" "$(cat "$arch/run.json" "$arch/transcript.jsonl" 2>&1)"
bash scripts/factory/archive.sh export demo "$work/demo-archive.tar.gz" >/dev/null && rm -rf "$arch" \
  && bash scripts/factory/archive.sh import "$work/demo-archive.tar.gz" >/dev/null && [ -f "$arch/run.json" ] \
  && bash scripts/factory/archive.sh list demo | grep -q '^r1abc	factory-worker	gw/maker-1	01-hello' \
  && t "archive: export, import and list round-trip" || fail "archive export" "$(bash scripts/factory/archive.sh list demo 2>&1)"
meta="$work/usage/run/r1abc_factory-worker_meta.json"; when="$(node -e 'const fs=require("fs");console.log(new Date(fs.statSync(process.argv[1]).mtimeMs-30000).toISOString())' "$meta")"
glog="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/guard.log"
printf '%s\tpush\tbash\t{"command":"git push origin main token=\\"glpat-abcdefghij0123456789\\""}\t%s\n' "$when" "$PWD" >> "$glog"
printf '%s\tpush\tbash\t{"command":"git push"}\t%s\n' "2001-01-01T00:00:00.000Z" "$PWD" >> "$glog"
FACTORY_USAGE_DIRS="$work/usage" bash scripts/factory/archive.sh collect demo >/dev/null
node -e 'const r=require(process.argv[1]+"/run.json"); process.exit(r.guard.length===1 && r.guard[0].rule==="push" && !/glpat-/.test(r.guard[0].input) ? 0 : 1)' "$arch" \
  && t "archive: the guard's refusals during the run are kept with it, redacted (audit trail)" || fail "archive guard" "$(cat "$arch/run.json")"
# D101: only this checkout's runs: another clone's run in a shared folder is ignored, one under a worktree of ours is kept.
printf '{"model":"gw/maker-1","usage":{"turns":2},"durationMs":1000,"transcriptPath":"/srv/other-clone/.pi/subagents/r9zzz.jsonl"}' > "$work/usage/run/r9zzz_factory-worker_meta.json"
printf 'Role: factory-worker. Mission demo, ticket 01-hello.\n\nbrief-id: 0123456789abcdef\n' > "$work/usage/run/r9zzz_factory-worker_input.md"
printf '{"model":"gw/maker-1","usage":{"turns":2},"durationMs":1000,"execution":{"cwd":"%s/src"}}' "$PWD" > "$work/usage/run/r8own_factory-worker_meta.json"
printf 'Role: factory-worker.\n\nbrief-id: fedcba9876543210\n' > "$work/usage/run/r8own_factory-worker_input.md"
out="$(FACTORY_USAGE_DIRS="$work/usage" bash scripts/factory/archive.sh collect demo)"
adir="$(dirname "$arch")"
[ ! -e "$adir/r9zzz_factory-worker" ] && [ -f "$adir/r8own_factory-worker/run.json" ] && grep -q '1 run(s) of another checkout ignored' <<<"$out" \
  && t "archive collect keeps only this checkout's runs: a foreign run is ignored (D101)" || fail "archive foreign" "$out $(ls "$adir")"
rm -f "$work/usage/run/r9zzz_"* "$work/usage/run/r8own_"*; rm -rf "$adir/r8own_factory-worker"
printf '#!/usr/bin/env bash\necho "$1" >> "%s"\nif grep -q "^# Failure mode" "$2" && grep -q "^# Tried to silence" "$2"; then echo "SCORE: fail"; echo "EVIDENCE: \\"added eslint-disable\\""; else echo "SCORE: pass"; echo "EVIDENCE: \\"none\\""; fi\n' "$work/judges.log" > "$work/judge.sh"; chmod +x "$work/judge.sh"
FACTORY_JUDGE_BIN="$work/judge.sh" FACTORY_JUDGE_MODELS="gw/maker-9 gw/judge-1" bash scripts/factory/score.sh demo >"$work/score.log" 2>&1 || fail "score" "$(cat "$work/score.log")"
grep -qx 'gw/judge-1' "$work/judges.log" && ! grep -q maker "$work/judges.log" \
  && grep -q '	silenced-check	fail	added eslint-disable$' $m/scores.tsv && grep -q '	no-reproduction	pass	none$' $m/scores.tsv \
  && t "score: each dimension judged by a model of another family; strict answers appended to scores.tsv" || fail "score" "$(cat "$work/score.log" $m/scores.tsv "$work/judges.log" 2>&1)"
n0="$(wc -l < $m/scores.tsv)"; FACTORY_JUDGE_BIN="$work/judge.sh" FACTORY_JUDGE_MODELS="gw/judge-1" bash scripts/factory/score.sh demo >/dev/null 2>&1
printf '#!/usr/bin/env bash\necho "I think it is fine"\n' > "$work/judge-bad.sh"; chmod +x "$work/judge-bad.sh"
FACTORY_JUDGE_BIN="$work/judge-bad.sh" FACTORY_JUDGE_MODELS="gw/judge-1" bash scripts/factory/score.sh demo --dimension silenced-check >"$work/score2.log" 2>&1
[ "$(wc -l < $m/scores.tsv)" = "$n0" ] && t "score: a run is judged once per dimension; a malformed answer is never guessed" || fail "score dedupe" "$(cat "$work/score2.log")"
FACTORY_JUDGE_BIN="$work/judge.sh" FACTORY_JUDGE_MODELS="gw/maker-2" bash scripts/factory/score.sh demo --dimension context-waste >"$work/score3.log" 2>&1
grep -q 'without a judge of another family' "$work/score3.log" && t "score: no judge of the run's own family" || fail "score family" "$(cat "$work/score3.log")"
echo 'https://gitlab.example/g/p/-/merge_requests/9' > $m/mr.url
bash scripts/factory/metrics.sh --all > "$work/all.md"; bash scripts/factory/metrics.sh --all --json > "$work/all.json"
grep -q '^| demo | ' "$work/all.md" && grep -q '^| \*\*Total\*\*' "$work/all.md" && grep -q 'Cost per MR' "$work/all.md" \
  && node -e 'const j=require(process.argv[1]); const d=j.missions.find(m=>m.mission==="demo"); process.exit(d && d.runs===1 && d.tokensIn===120000 && d.scored>=2 && d.scoreFails>=1 && d.mr && j.total.mrs===1 ? 0 : 1)' "$work/all.json" \
  && grep -q 'Scored runs (scores.tsv, D97) | .*fail' <<<"$(bash scripts/factory/metrics.sh demo)" \
  && t "metrics --all: every mission and the total, with cost per MR and scores (D97)" || fail "metrics all" "$(cat "$work/all.md" "$work/all.json")"
rm -f $m/mr.url $m/scores.tsv
# D87: the hook's dependency link never costs a round.
ln -s "$work" node_modules; echo 'export const extra = 1;' > src/tools/extra.js
git add -N node_modules src/tools/extra.js; git diff --relative > "$work/hook.patch"; git reset -q node_modules src/tools/extra.js; rm -f node_modules src/tools/extra.js
node scripts/factory/patch-paths.mjs strip-hook "$work/hook.patch" "$work/hook.clean" "node_modules .venv" 2>"$work/strip.log"
! grep -q node_modules "$work/hook.clean" && grep -q 'src/tools/extra.js' "$work/hook.clean" && grep -q 'dropped node_modules' "$work/strip.log" \
  && bash scripts/factory/patch-guard.sh "$work/hook.clean" >/dev/null && ! bash scripts/factory/patch-guard.sh "$work/hook.patch" >/dev/null \
  && t "a worktree's node_modules link is dropped from the patch before the guard; other links still block (D87)" || fail "strip hook" "$(cat "$work/strip.log" "$work/hook.clean")"
# D88: a misspelled frozen-paths heading stops the mission.
cp $m/spec.md "$work/spec.keep"; printf '\n## Frozen path\n- src/\n' >> $m/spec.md
out="$(bash scripts/factory/next.sh demo)"; cp "$work/spec.keep" $m/spec.md
echo "$out" | grep -q '^STEP: blocked' && echo "$out" | grep -q 'must be exactly "## Frozen paths"' \
  && t "next.sh blocks a misspelled '## Frozen paths' heading (D88)" || fail "frozen heading" "$out"
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

# .skip( in source code is pagination, not a skipped test; in a test file it is.
hs="$work/health-skip"; mkdir -p "$hs/src" "$hs/test"; (cd "$hs" && git init -q \
  && printf 'export const page = (q) => q.skip(10).limit(5);\n' > src/repo.js \
  && printf 'it.skip("later", () => {});\n' > test/a.spec.js && git add -A && git commit -qm init)
m1="$(cd "$hs" && bash "$root/scripts/factory/health.sh" metrics 2>&1)"
grep -q '"skipped_tests": 1' <<<"$m1" && t "health: skipped tests count in test files only (a query's .skip( isn't one)" || fail "skip counter" "$m1"

hd="$work/health-details"; mkdir -p "$hd/src"; (cd "$hd" && git init -q \
  && for f in one two; do printf 'export function %s(a, b) {\n  const x = a + b;\n  const y = x * 2;\n  const z = y - a;\n  const w = z / b;\n  const v = w + x;\n  return v + y + z;\n}\n' "$f" > src/$f.js; done \
  && git add -A && git commit -qm init)
d1="$(cd "$hd" && bash "$root/scripts/factory/health.sh" details 2>&1)"
grep -qE '^dup src/two.js:[0-9]+ = src/one.js:[0-9]+$' <<<"$d1" && t "health details: where each finding is, for the depth step (D104)" || fail "health details" "$d1"

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
node -e 'const j=require(process.argv[1]); process.exit(j.factory && j.factory.missions>=1 && "costPerMr" in j.factory ? 0 : 1)' "$work/all.json" \
  && t "status.sh --all: the factory's totals across missions, for the factory engineer (D97)" || fail "status factory" "$(head -c 600 "$work/all.json")"
rm -f $m/state/open-question.md
here_branch="$(git branch --show-current)"; git switch -q -c cockpit-side; echo side > $m/state/side.txt; git add $m/state/side.txt; git commit -qm "test: state on another branch"; git switch -q "$here_branch"
bash scripts/factory/status.sh --all --json > "$work/all.json"
node -e '
const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const m = s.missions.find((x) => x.name === "demo");
process.exit(m && m.step === "other-branch" && m.otherBranch === "cockpit-side" && !m.human && m.needs.length === 0 ? 0 : 1);' "$work/all.json" \
  && t "status.sh: a mission whose state is on another branch shows where, not as needs-you" || fail "status other branch" "$(head -c 1500 "$work/all.json")"
git branch -q -D cockpit-side
bash scripts/factory/cockpit.sh --once "$work/cockpit" >/dev/null && [ -s "$work/cockpit/index.html" ] && grep -q '"missions"' "$work/cockpit/state.json" \
  && [ -z "$(git status --porcelain -- .scratch)" ] && t "cockpit.sh --once writes the page and its snapshot outside the repo, read-only" || fail "cockpit once" "$(ls "$work/cockpit"; git status --porcelain)"

# D86: one command opens the MR from /pr's body.
out="$(FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo --dry-run 2>&1)" && fail "mr.sh must refuse without a PR body"
echo "$out" | grep -q 'run /pr first' && t "mr.sh refuses without a PR body" || fail "mr no body" "$out"
printf '# test(demo): characterize the hello tools\n\n## Summary\n\nTwo tools pinned.\n' > $m/pr.md
out="$(FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo --dry-run 2>&1)"
echo "$out" | grep -q "→ production" && echo "$out" | grep -q 'title: test(demo): characterize the hello tools' && echo "$out" | grep -q 'reviewer: jdoe' \
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
FACTORY_DATA_DIR="$work/data" GLAB_LOG="$work/glab.log" PATH="$work/bin:$PATH" FACTORY_MR_TARGET=production bash scripts/factory/mr.sh demo >"$work/mr.log" 2>&1 || fail "mr glab" "$(cat "$work/mr.log")"
git ls-remote --heads "$work/origin.git" "$cur" | grep -q . && grep -qx 'production' "$work/glab.log" && grep -qx 'test(demo): characterize the hello tools' "$work/glab.log" \
  && grep -q '^## Summary' "$work/glab.log" && ! grep -q '^# test' "$work/glab.log" && grep -q 'merge_requests/7' $m/mr.url \
  && t "mr.sh pushes the branch and opens the MR with glab; heading becomes the title, the rest the description (D86)" || fail "mr glab create" "$(cat "$work/mr.log" "$work/glab.log")"
ls "$work/data"/*/demo-*.tar.gz >/dev/null 2>&1 && tar -tzf "$work/data"/*/demo-*.tar.gz | grep -q 'demo/metrics.json' \
  && t "mr.sh keeps the mission's data: metrics next to its runs, one export in the machine's data folder (D103)" || fail "mission data" "$(ls -R "$work/data" 2>&1; cat "$work/mr.log")"
git remote remove origin; rm -f $m/pr.md $m/mr.url

# D96: new tests must disagree with the code before the change, as the intent says.
echo "Test on base (D96)"
tob0="$(git rev-parse HEAD)"
printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD='"'"'for f in tests/tob/*.check; do [ -e "$f" ] || continue; sh "$f" || exit 1; done'"'"'\n' > .factory/commands.env
mkdir -p src/tob tests/tob; echo 1 > src/tob/value.txt
for i in feature bugfix maintenance refactor; do
  mkdir -p .scratch/tob-$i/issues
  printf '# Tob\n**Intent:** %s\n\n## Frozen paths\n- none\n\n## Validation contract\n' "$i" > .scratch/tob-$i/spec.md
  printf '# 01 a\n## Covers\nVAL-T-001\n' > .scratch/tob-$i/issues/01-a.md
done
printf '# 01 a\n## Covers\nVAL-T-001\n\n## Test on base: skip — the fixture regenerates a snapshot\n' > .scratch/tob-feature/issues/02-b.md
git add -A; git commit -qm "test: test-on-base missions"; tobbase="$(git rev-parse HEAD)"
tob_patch() {   # <name> <expected value in the test> [new value in the code]
  { printf 'diff --git a/tests/tob/%s.check b/tests/tob/%s.check\nnew file mode 100644\n--- /dev/null\n+++ b/tests/tob/%s.check\n@@ -0,0 +1 @@\n+grep -qx %s src/tob/value.txt\n' "$1" "$1" "$1" "$2"
    [ -z "${3:-}" ] || printf 'diff --git a/src/tob/value.txt b/src/tob/value.txt\n--- a/src/tob/value.txt\n+++ b/src/tob/value.txt\n@@ -1 +1 @@\n-1\n+%s\n' "$3"; } > "$work/tob-$1.patch"; }
tob_int() { git reset -q --hard "$tobbase"; bash scripts/factory/integrate.sh "tob-$1" "${3:-01-a}" "$work/tob-$2.patch" > "$work/tob.log" 2>&1; }
tob_patch adds 2 2; tob_patch pins 1; tob_patch wrong 3
tob_int feature adds && grep -q 'test on base: as expected (fails before the change)' "$work/tob.log" \
  && t "feature: a new test that fails on the code before the change integrates (D96)" || fail "tob feature ok" "$(cat "$work/tob.log")"
if tob_int feature pins; then fail "feature: a test passing before the change must be refused" "$(cat "$work/tob.log")"; fi
[ "$(bash -c '. scripts/factory/lib.sh; verdict_field .scratch/tob-feature/verdicts/01-a-code.md Brief')" = test-on-base ] \
  && grep -q "pass on the code before the change (feature mission): they don't test the ticket" .scratch/tob-feature/verdicts/01-a-code.md \
  && [ ! -e tests/tob/pins.check ] && t "feature: a new test that already passes before the change is a failed round, nothing applied" || fail "tob feature refuse" "$(cat "$work/tob.log" .scratch/tob-feature/verdicts/01-a-code.md 2>&1)"
if tob_int bugfix pins; then fail "bugfix: a test passing before the fix must be refused" "$(cat "$work/tob.log")"; fi
t "bugfix: the same rule (the test must reproduce the bug first)"
tob_int maintenance pins && grep -q "passes on today's code" "$work/tob.log" || fail "tob maintenance ok" "$(cat "$work/tob.log")"
if tob_int maintenance wrong; then fail "maintenance: a test failing on today's code must be refused" "$(cat "$work/tob.log")"; fi
grep -q "fail on today's code (maintenance mission): a characterization test must describe current behavior" .scratch/tob-maintenance/verdicts/01-a-code.md \
  && t "maintenance: a characterization test must pass on today's code" || fail "tob maintenance refuse" "$(cat .scratch/tob-maintenance/verdicts/01-a-code.md)"
tob_int refactor pins || fail "tob refactor ok" "$(cat "$work/tob.log")"
if tob_int refactor wrong; then fail "refactor: a test failing on today's code must be refused" "$(cat "$work/tob.log")"; fi
t "refactor: new tests must pass on the code before the refactor"
tob_int feature pins 02-b && grep -q 'skipped by the ticket (the fixture regenerates a snapshot)' "$work/tob.log" \
  && grep -qP '\t02-b\ttest-on-base\t.*\tYes: the fixture regenerates a snapshot\t' .scratch/tob-feature/decisions.tsv \
  && t "a ticket can opt out with a reason, recorded as a decision" || fail "tob opt-out" "$(cat "$work/tob.log" .scratch/tob-feature/decisions.tsv 2>&1)"
git reset -q --hard "$tobbase"
out="$(bash scripts/factory/test-on-base.sh tob-feature 01-a "$work/tob-pins.patch" "$tobbase")" && fail "test-on-base.sh must exit 1 on a mismatch" "$out"
bash scripts/factory/test-on-base.sh tob-feature 01-a "$work/tob-adds.patch" "$tobbase" | grep -q 'as expected' \
  && { bash scripts/factory/test-on-base.sh tob-feature 01-a "$work/none.patch" >/dev/null 2>&1; [ $? -eq 2 ]; } \
  && [ "$(git rev-parse HEAD)" = "$tobbase" ] && [ -z "$(git status --porcelain --untracked-files=no)" ] \
  && t "test-on-base.sh: the same check on its own (exit 0, 1, 2), the branch untouched" || fail "tob script" "$out"
# D101: errors are errors, a red base is inconclusive, only the patch's tests with FACTORY_TEST_FILES_CMD, cleanup on any exit.
tob_rc() { rc=0; out="$(bash scripts/factory/test-on-base.sh "$@" 2>&1)" || rc=$?; }
printf 'diff --git a/tests/tob/zz.check b/tests/tob/zz.check\n--- a/tests/tob/zz.check\n+++ b/tests/tob/zz.check\n@@ -1 +1 @@\n-nothing here\n+grep -qx 2 src/tob/value.txt\n' > "$work/tob-noapply.patch"
tob_rc tob-feature 01-a "$work/tob-noapply.patch" "$tobbase"
[ "$rc" = 2 ] && grep -q "test on base: error: the tests don't apply on" <<<"$out" || fail "tob: a patch that doesn't apply is an error" "$rc $out"
tob_int feature noapply && fail "integrate must fail a round whose tests don't apply on base" "$(cat "$work/tob.log")"
grep -q "error: the tests don't apply" .scratch/tob-feature/verdicts/01-a-code.md && t "test on base: tests that don't apply on the base are an error, a failed round, never 'not checked' (D101)" || fail "tob noapply verdict" "$(cat "$work/tob.log")"
git reset -q --hard "$tobbase"
printf 'FACTORY_TEST_CMD="definitely-not-a-command-xyz"\n' >> .factory/commands.env
tob_rc tob-feature 01-a "$work/tob-adds.patch" "$tobbase"
[ "$rc" = 2 ] && grep -q "error: the test command can't start" <<<"$out" && t "test on base: a test command that can't start is an error (D101)" || fail "tob can't start" "$rc $out"
git checkout -q -- .factory/commands.env
mkdir -p tests/tob; echo 'exit 1' > tests/tob/red.check; git add -A; git commit -qm "test: a red base"; redbase="$(git rev-parse HEAD)"
tob_rc tob-feature 01-a "$work/tob-adds.patch" "$redbase"
[ "$rc" = 2 ] && grep -q 'inconclusive: base already red: set FACTORY_TEST_FILES_CMD' <<<"$out" || fail "tob red base" "$rc $out"
git reset -q --hard "$redbase"; bash scripts/factory/integrate.sh tob-feature 01-a "$work/tob-adds.patch" > "$work/tob.log" 2>&1 && fail "a red base must fail the round" "$(cat "$work/tob.log")"
grep -q 'base already red' .scratch/tob-feature/verdicts/01-a-code.md && t "feature on a red base: inconclusive, recorded, the round fails (D101)" || fail "tob red verdict" "$(cat "$work/tob.log")"
git reset -q --hard "$redbase"
printf '%s\n' 'FACTORY_TEST_FILES_CMD='"'"'for f in {files}; do sh "$f" || exit 1; done'"'" >> .factory/commands.env
tob_rc tob-feature 01-a "$work/tob-adds.patch" "$redbase"; r1="$rc $out"
tob_rc tob-feature 01-a "$work/tob-pins.patch" "$redbase"
[ "${r1%% *}" = 0 ] && grep -q 'as expected' <<<"$r1" && [ "$rc" = 1 ] \
  && t "FACTORY_TEST_FILES_CMD runs only the patch's test files: a red base doesn't matter (D101)" || fail "tob files cmd" "$r1 / $rc $out"
git reset -q --hard "$tobbase"
printf 'FACTORY_TEST_CMD="sleep 30"\n' >> .factory/commands.env
wt0="$(git worktree list | wc -l)"
setsid bash scripts/factory/test-on-base.sh tob-feature 01-a "$work/tob-adds.patch" "$tobbase" > "$work/tob-int.log" 2>&1 & tobpid=$!
for _ in $(seq 100); do [ "$(git worktree list | wc -l)" -gt "$wt0" ] && break; sleep 0.1; done
[ "$(git worktree list | wc -l)" -gt "$wt0" ] || fail "tob: no temporary worktree to interrupt" "$(cat "$work/tob-int.log")"
kill -TERM -- "-$tobpid" 2>/dev/null || true; wait "$tobpid" 2>/dev/null || true
for _ in $(seq 50); do [ "$(git worktree list | wc -l)" = "$wt0" ] && break; sleep 0.1; done
[ "$(git worktree list | wc -l)" = "$wt0" ] && t "test on base: an interrupt still removes its temporary worktree (trap, D101)" || fail "tob trap" "$(git worktree list)"
git checkout -q -- .factory/commands.env
FACTORY_TEST_ON_BASE=0 bash scripts/factory/integrate.sh tob-feature 01-a "$work/tob-pins.patch" > "$work/tob.log" 2>&1 && grep -q 'test on base: off' "$work/tob.log" \
  && t "FACTORY_TEST_ON_BASE=0 turns the check off" || fail "tob off" "$(cat "$work/tob.log")"
git reset -q --hard "$tobbase"
git worktree add -q -b pi-subagents/01-a-tob-s0-t0 "$work/tob-wt" "$tobbase"
tob_sub="$(git rev-parse --show-prefix)"
( cd "$work/tob-wt/${tob_sub}" && mkdir -p tests/tob && echo 'grep -qx 1 src/tob/value.txt' > tests/tob/w.check && bash scripts/factory/self-check.sh tob-feature ) > "$work/tob-sc.log" 2>&1 && fail "self-check must refuse a test passing before the change" "$(cat "$work/tob-sc.log")"
grep -q '^SELF-CHECK: FAIL test-on-base' "$work/tob-sc.log" && t "self-check runs the same check, so the worker sees it before handing over" || fail "tob self-check" "$(cat "$work/tob-sc.log")"
git worktree remove --force "$work/tob-wt"; git branch -q -D pi-subagents/01-a-tob-s0-t0
git reset -q --hard "$tob0"

# D91: the scripted lead runs a mission's loop with no LLM lead.
echo "Scripted lead (run.sh)"
r=.scratch/runner; mkdir -p $r/issues
printf '# Runner\n**Intent:** feature\n\nA run file.\n\n## Validation contract\n\n### VAL-RUN-001: runs\n**Kind:** code\nGiven the tool, when it runs, then it returns ok.\n' > $r/spec.md
printf 'FACTORY_LINT_CMD="true"\nFACTORY_TEST_CMD="true"\nFACTORY_TEST_ON_BASE=0\n' > .factory/commands.env   # "true" can't fail on base (D96 is tested on its own)
git add -A; git commit -qm "test: runner mission"
mkdir -p "$work/bin"
# A pi stand-in: checks how run.sh calls it, plays the contract wave, prints pi's JSON events.
cat > "$work/bin/fakepi" <<'PI'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$PI_ARGS_LOG"; echo "$FACTORY_DRIVE_WORKFLOW" >> "$PI_ARGS_LOG"
echo "No findings. Critique result: approve" > .scratch/runner/contract-critique.md
echo '{"type":"session"}'
echo '{"type":"tool_execution_end","toolName":"subagent","isError":false,"result":{"content":[{"type":"text","text":"Workflow completed."}],"details":{"workflow":{"value":[{"key":"contract-critic","output":"approve"}]}}}}'
PI
chmod +x "$work/bin/fakepi"; mkdir -p "$work/pi dir"; cp "$work/bin/fakepi" "$work/pi dir/pi bin"
out="$(PI_ARGS_LOG="$work/pi.args" FACTORY_PI_BIN="$work/pi dir/pi bin" bash scripts/factory/run.sh runner --no-preflight 2>&1)" || fail "run.sh contract" "$out"
grep -q -- '-p --mode json' "$work/pi.args" && grep -q 'driver.mjs --model factory-driver/script' "$work/pi.args" && grep -q 'workflows/.*-contract.js' "$work/pi.args" \
  && echo "$out" | grep -q '^STEP: approve' && echo "$out" | grep -q 'WAITING: human (approve)' \
  && grep -q -- '--approve' "$work/pi.args" \
  && t "run.sh: pi in JSON mode (path with spaces, project trusted so the guard loads) with the driver as the model runs the contract wave, then stops at G1 (D91)" || fail "run.sh pi-json" "$out
$(cat "$work/pi.args")"
bash scripts/factory/human.sh approve runner >/dev/null
# The fake runner plays every agent from the wave file, as the real ones would write.
ok_patch run.test.js 'ok' 2>/dev/null || printf 'diff --git a/tests/run.test.js b/tests/run.test.js\nnew file mode 100644\n--- /dev/null\n+++ b/tests/run.test.js\n@@ -0,0 +1 @@\n+ok\n' > "$work/run.test.js.patch"
cat > "$work/bin/fakerun" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
wf="$1"; r=.scratch/runner; . scripts/factory/lib.sh; mkdir -p $r/verdicts
bid() { node -e 'const s=require("fs").readFileSync(process.argv[1],"utf8");const m=s.match(/const ITEMS = (\[[\s\S]*?\n\]);/);const it=JSON.parse(m[1]).find(i=>i.key===process.argv[2])||JSON.parse(m[1])[0];console.log((it.task.match(/brief-id: (\S+)/)||[])[1]||"")' "$wf" "$1"; }
bcommit() { local sha t; for sha in $(grep -oE '[0-9a-f]{40}' "$wf" | sort -u); do for t in - ""; do [ "$(brief_id "$1" runner "$t" "$sha")" = "$2" ] && { echo "$sha"; return; }; done; done; }
echo "$(basename "$wf")" >> "$FAKE_LOG"
case "$wf" in
  *-design*.js) printf '# Design: runner\n\n## Slices\n1. run end to end — VAL-RUN-001\n' > $r/design.md; echo '{"output":"design"}' ;;
  *-tickets*.js) printf '# 01 run\n**Size:** S\n## Covers\nVAL-RUN-001\n' > $r/issues/01-run.md; echo '{"output":"1 ticket"}' ;;
  *-build-wave*.js)
    if [ ! -f "$FAKE_STATE.429" ]; then touch "$FAKE_STATE.429"; echo '[{"ticket":"01-run","patch":null,"ok":false,"error":"429 Too Many Requests: rate limit"}]'
    else echo "[{\"ticket\":\"01-run\",\"patch\":\"$FAKE_PATCH\",\"ok\":true}]"; fi ;;
  *-review-wave*.js)
    printf '# Verdict: 01-run\n**Result:** PASS\n**Commit:** %s\n**Brief:** %s\n\n## Assertions\n- VAL-RUN-001: PASS — tests/run.test.js "runs"\n' "$(ticket_marker runner 01-run)" "$(bid 01-run)" > $r/verdicts/01-run-code.md
    echo '[{"ticket":"01-run","output":"PASS"}]' ;;
  *-validate*.js)
    printf '# Verdict: behavior\n**Result:** PASS\n**Commit:** %s\n**Brief:** %s\n\n## Assertions\n- VAL-RUN-001: PASS — tests/run.test.js\n' "$(bcommit validator "$(bid behavior)")" "$(bid behavior)" > $r/verdicts/behavior.md
    echo '{"output":"PASS"}' ;;
  *-steward*.js)
    { printf '# Verdict: health\n**Result:** PASS\n**Commit:** %s\n**Brief:** %s\n\n## Bar\n' "$(bcommit code-steward "$(bid code-steward)")" "$(bid code-steward)"
      for q in QB-SAFE-01 QB-CLEAR-01 QB-TEST-01 QB-PRED-01; do echo "- $q: PASS — tests/run.test.js reviewed"; done
      printf '\n## Explanations\n### tests/run.test.js\nWhat, how, what can go wrong.\n\n## Findings\n- none\n'; } > $r/verdicts/health.md
    echo '{"output":"PASS"}' ;;
  *) echo "unexpected wave $wf"; exit 1 ;;
esac
FAKE
chmod +x "$work/bin/fakerun"
export FAKE_LOG="$work/fake.log" FAKE_STATE="$work/fake" FAKE_PATCH="$work/run.test.js.patch"
out="$(FACTORY_RUNNER=fake FACTORY_FAKE_RUNNER="$work/bin/fakerun" bash scripts/factory/run.sh runner --no-preflight 2>&1)" || fail "run.sh design" "$out"
echo "$out" | grep -q 'WAITING: human (approve-design)' && [ -f $r/design.md ] && t "run.sh: design wave, then stops for G1b (D94)" || fail "run.sh design" "$out"
bash scripts/factory/human.sh approve runner design >/dev/null
out="$(FACTORY_RUNNER=fake FACTORY_FAKE_RUNNER="$work/bin/fakerun" bash scripts/factory/run.sh runner --no-preflight 2>&1)" || fail "run.sh tickets" "$out"
echo "$out" | grep -q 'WAITING: human (approve-tickets)' && [ -f $r/issues/01-run.md ] && t "run.sh: tickets wave, then stops for the human's approval" || fail "run.sh tickets" "$out"
bash scripts/factory/human.sh approve runner tickets >/dev/null
rc=0; out="$(FACTORY_RUNNER=fake FACTORY_FAKE_RUNNER="$work/bin/fakerun" bash scripts/factory/run.sh runner --no-preflight 2>&1)" || rc=$?
[ "$rc" = 3 ] && [ -f $r/state/PAUSED.md ] && [ ! -f $r/verdicts/01-run-code.md ] && echo "$out" | grep -q 'provider error' \
  && t "run.sh: a 429 from a worker pauses the mission, no round, exit 3 (D58)" || fail "run.sh provider" "rc=$rc $out"
out="$(FACTORY_RUNNER=fake FACTORY_FAKE_RUNNER="$work/bin/fakerun" bash scripts/factory/run.sh runner --no-preflight 2>&1)" || fail "run.sh to pr" "$out"
echo "$out" | grep -q '^STEP: pr' && echo "$out" | grep -q 'WAITING: human (pr)' && [ -f tests/run.test.js ] \
  && grep -q 'review-wave' "$FAKE_LOG" && grep -q 'validate' "$FAKE_LOG" && grep -q 'steward' "$FAKE_LOG" \
  && t "run.sh: resumes, builds, integrates, reviews, validates, checks health and stewards up to the MR, unattended" || fail "run.sh to pr" "$out"
runlogs="$(git rev-parse --path-format=absolute --git-common-dir)/pi-factory/runs/runner"
! compgen -G "$r/logs/*.jsonl" >/dev/null && ! compgen -G "$r/logs/*.result.json" >/dev/null && [ -z "$(git ls-files $r | grep -E 'jsonl|result\.json|\.err$')" ] && ls "$runlogs"/*-contract.jsonl >/dev/null 2>&1 && ls "$runlogs"/*-review-wave.result.json >/dev/null 2>&1 \
  && t "run.sh keeps raw runner output in the git folder, never in the committed mission folder" || fail "run logs" "$(ls -R $r "$runlogs" 2>&1 | head -40)"
pe() { bash -c '. scripts/factory/lib.sh; provider_error_line "$1"' _ "$1"; }
[ -n "$(pe 'Error: 429 Too Many Requests')" ] && [ -n "$(pe 'HTTP 503 Service Unavailable')" ] && [ -n "$(pe 'rate limit exceeded')" ] \
  && [ -z "$(pe 'Tests: 500 passed, 2 failed')" ] && [ -z "$(pe 'expected 500, got 404')" ] \
  && t "provider errors are recognised by their shape, not by any 429 or 5xx in the text" || fail "provider_error_line"
bash scripts/factory/gate.sh mission runner >"$work/gate.log" 2>&1 && t "the mission run.sh drove passes the gates (G1-G5)" || fail "run.sh gate" "$(cat "$work/gate.log")"
out="$(FACTORY_RUNNER=fake FACTORY_FAKE_RUNNER=/bin/false bash scripts/factory/run.sh runner --no-preflight --max-steps 0 2>&1)" && fail "run.sh must stop past --max-steps"
echo "$out" | grep -q 'more than 0 steps' && t "run.sh: a step budget stops a loop that would not end" || fail "max steps" "$out"
unset FAKE_LOG FAKE_STATE FAKE_PATCH

# D98: the benchmark replays a real ticket with another model setup, scored by the gates.
echo "Benchmark (D98)"
head_before="$(git rev-parse HEAD)"; branch_before="$(git rev-parse --abbrev-ref HEAD)"
cat > "$work/bin/fakebench" <<'FB'
#!/usr/bin/env bash
# <role> <case> <work-dir> <brief> <model> <thinking> <out-dir>
set -euo pipefail
role="$1" wd="$3" brief="$4" model="$5" thinking="$6" out="$7"
echo "$role $2 $model $thinking role=${FACTORY_ROLE:-}" >> "$BENCH_LOG"
grep -q 'brief-id:' "$brief" || { echo "no brief"; exit 1; }
if [ "$role" = reviewer ]; then
  m="${2%%--*}" tk="${2#*--}"; mkdir -p "$wd/.scratch/$m/verdicts"
  printf '# Verdict: %s\n**Result:** %s\n' "$tk" "$([ "$model" = gw/judge-1 ] && echo PASS || echo FAIL)" > "$wd/.scratch/$m/verdicts/$tk-code.md"; exit 0
fi
[ "$role" = worker ] || exit 1
case "$model" in
  gw/maker-3) mkdir -p "$wd/.github"; echo x > "$wd/.github/ci.yml"; cost=0.1 ;;
  gw/maker-hang) sleep 30; cost=0 ;;
  gw/maker-2) mkdir -p "$wd/tests"; echo 'ok' > "$wd/tests/bench.test.js"; cost=0.2 ;;
  *) mkdir -p "$wd/tests"; echo 'ok' > "$wd/tests/bench.test.js"; cost=0.5 ;;
esac
printf '{"turns":7,"input":1000,"output":200,"cost":%s}' "$cost" > "$out/usage.json"
FB
chmod +x "$work/bin/fakebench"
export BENCH_LOG="$work/bench.log" FACTORY_BENCH_RUNNER="$work/bin/fakebench"
printf '{"agents":{"factory-worker":{"model":"gw/maker-1","thinking":"medium"}}}' > "$work/p1.json"
printf '{"agents":{"factory-worker":{"model":"gw/maker-2","thinking":"medium"}}}' > "$work/p2.json"
printf '{"agents":{"factory-worker":{"model":"gw/maker-3","thinking":"high"}}}' > "$work/p3.json"
int="$(git log --format='%H %s' | awk '$2 == "feat(runner):" && $3 == "01-run" { print $1 }' | tail -1)"
bash scripts/factory/bench.sh add runner 01-run --area tooling --why "first ticket" >/dev/null
c=.factory/bench/cases/runner--01-run
[ "$(bash -c '. scripts/factory/lib.sh; awk -F"\t" "NR == 2 { print \$7, \$9, \$5, \$6 }" .factory/bench/cases.tsv')" = "easy $(git rev-parse "$int^") regression worker" ] \
  && [ -f $c/issue.md ] && [ -f $c/spec.md ] && grep -q '"first_pass": true' $c/case.json \
  && t "bench add: a case snapshots its ticket, starts before its first integration, easy because it passed first time" || fail "bench add" "$(cat .factory/bench/cases.tsv $c/case.json)"
out="$(bash scripts/factory/bench.sh add runner 01-run 2>&1)" && fail "bench add must refuse a duplicate"
out="$(bash scripts/factory/bench.sh run default --config "$work/p1.json" --label m1 2>&1)" || fail "bench run m1" "$out"
grep -qP '^runner--01-run\teasy\ttooling\tyes\t-\t7\t1200\t0.5\t' .factory/bench/results/m1.tsv && grep -q 'worker runner--01-run gw/maker-1 medium' "$BENCH_LOG" \
  && [ "$(git rev-parse HEAD)" = "$head_before" ] && [ "$(git rev-parse --abbrev-ref HEAD)" = "$branch_before" ] && [ ! -e tests/bench.test.js ] \
  && [ -z "$(git worktree list | grep 'pi-factory/bench/wt-')" ] \
  && t "bench run: the case passes the gates in a throwaway worktree; the real branch is untouched" || fail "bench run" "$out
$(cat .factory/bench/results/m1.tsv)"
bash scripts/factory/bench.sh run default --config "$work/p2.json" --label m2 >/dev/null 2>&1 || fail "bench run m2"
out="$(bash scripts/factory/bench.sh run default --config "$work/p3.json" --label m3 2>&1)" || fail "bench run m3" "$out"
grep -qP '^runner--01-run\teasy\ttooling\tno\tguard\t' .factory/bench/results/m3.tsv && echo "$out" | grep -q '0/1 passed' \
  && t "bench run: a patch the guard refuses fails the case, with the gate named" || fail "bench gate" "$out"
out="$(bash scripts/factory/bench.sh run default --config "$work/p1.json" --label dbg --case runner--01-run --debug 2>&1)" || fail "bench debug" "$out"
kept="$(sed -n 's/^bench: kept \(.*\) (transcript.*/\1/p' <<<"$out")"
[ -n "$kept" ] && [ -f "$kept/tests/bench.test.js" ] && git worktree remove --force "$(git -C "$kept" rev-parse --show-toplevel)" \
  && t "bench run --case --debug: one case, worktree kept for inspection" || fail "bench debug" "$out"
printf '{"agents":{"factory-worker":{"model":"gw/maker-1","thinking":"medium"},"factory-reviewer":{"model":"gw/judge-2"}}}' > "$work/p4.json"
bash scripts/factory/bench.sh run default --config "$work/p4.json" --label rv --review >/dev/null 2>&1 || fail "bench review"
grep -qP '^runner--01-run\teasy\ttooling\tno\treview\t' .factory/bench/results/rv.tsv && grep -q 'reviewer runner--01-run gw/judge-2' "$BENCH_LOG" \
  && t "bench run --review: a case that passes the gates is reviewed; a FAIL verdict fails it" || fail "bench review" "$(cat .factory/bench/results/rv.tsv)"
out="$(bash scripts/factory/bench.sh compare m1 m2 m3 --name trio 2>&1)" || fail "bench compare" "$out"
head -1 <<<"$out" | grep -q '^3 configurations on suite default, 1 cases each, against the default m1; one variable changed in m2 (worker model: gw/maker-2)' \
  && grep -q '^highest quality  m2' <<<"$out" && grep -q '^most efficient   m2' <<<"$out" && grep -q '^lowest cost      m2' <<<"$out" \
  && grep -q 'Below the floor, never recommended: m3 (0%)' <<<"$out" && grep -qP '^m3\t0%\t\$0.10\t7\t\d+\tbelow the floor' <<<"$out" \
  && grep -q '⚠ m3 differs from m1 by 2 variables (worker model, worker thinking)' <<<"$out" \
  && node -e 'const c=require(process.argv[1]),p=(l)=>c.points.find(x=>x.label===l);process.exit(c.points.length===3&&p("m2").pareto&&!p("m1").pareto&&!p("m3").pareto&&p("m3").below_floor&&Math.abs(c.floor-0.9)<1e-9&&c.axes.includes("cost_per_trial")?0:1)' "$PWD/.factory/bench/compare/trio.json" \
  && t "bench compare: the answer first, cost recommendations only above the quality floor, a warning when two variables changed, the cockpit's points" || fail "bench compare" "$out"
bash scripts/factory/bench.sh run default --config "$work/p3.json" --label m3b >/dev/null 2>&1 || fail "bench run m3b"
out="$(bash scripts/factory/bench.sh compare m3 m3b --min-pass 50 --name floorless 2>&1)" || fail "bench compare floor" "$out"
grep -q '^most efficient   none: no configuration reaches the quality floor (50%)' <<<"$out" && grep -q '^lowest cost      none: no configuration reaches' <<<"$out" \
  && grep -q 'No configuration reaches the quality floor of 50%, so none is recommended on cost' <<<"$out" \
  && t "bench compare: when nothing reaches the floor (--min-pass), the cost recommendations say so instead of naming a config" || fail "bench floor" "$out"
if bash scripts/factory/bench.sh compare m1 m3 --strict >/dev/null 2>&1; then fail "compare --strict must refuse a two-variable comparison"; fi
[ ! -f .factory/bench/compare/m1-vs-m3.json ] || fail "a refused comparison must write nothing"
bash scripts/factory/status.sh --all --json > "$work/state-bench.json" 2>/dev/null
node -e 'const s=require(process.argv[1]);const c=s.bench.find(b=>b.name==="trio");process.exit(c&&c.recommendations.length===3&&c.points.length===3?0:1)' "$work/state-bench.json" \
  && t "the cockpit snapshot carries the comparisons for the Benchmarks view" || fail "bench in snapshot" "$(head -c 600 "$work/state-bench.json")"
printf '# 02 follow-up\n**Size:** S\n## Covers\nVAL-RUN-001\nAdd a second line to the run file.\n' > "$work/02-followup.md"
bash scripts/factory/bench.sh add-file "$work/02-followup.md" runner --area tooling >/dev/null
out="$(bash scripts/factory/bench.sh probe default --config "$work/p2.json" 2>&1)" || fail "bench probe" "$out"
lab="probe-$(git rev-parse --short HEAD)-p2"
grep -qP '^runner--02-followup\tmedium\ttooling\tyes\t' ".factory/bench/results/$lab.tsv" && ! grep -q 'runner--01-run' ".factory/bench/results/$lab.tsv" \
  && grep -q '"probe": true' ".factory/bench/results/$lab.json" \
  && t "bench probe: follow-up cases run on today's code (how easy it is to change), regression cases don't" || fail "bench probe" "$out"
# D101: bench agents run as workers, never unguarded, and leave no worktree behind.
grep -q 'worker runner--01-run gw/maker-1 medium role=worker' "$BENCH_LOG" && t "bench agents run with FACTORY_ROLE=worker (the guard's worker rules, D101)" || fail "bench role" "$(cat "$BENCH_LOG")"
out="$(bash scripts/factory/bench.sh probe default --config "$work/p2.json" --at "$(git rev-list --max-parents=0 HEAD | tail -1)" --label noguard 2>&1)" && fail "bench must refuse a case without the guard" "$out"
grep -q "won't run agents without the factory guard" <<<"$out" && [ -z "$(git worktree list | grep 'pi-factory/bench/wt-')" ] \
  && t "bench refuses a case worktree without the guard extension, and removes it (D101)" || fail "bench no guard" "$out $(git worktree list)"
printf '{"agents":{"factory-worker":{"model":"gw/maker-hang","thinking":"low"}}}' > "$work/p5.json"
setsid bash scripts/factory/bench.sh run default --config "$work/p5.json" --label hang > "$work/bench-hang.log" 2>&1 & bpid=$!
for _ in $(seq 150); do git worktree list | grep -q 'pi-factory/bench/wt-hang' && break; sleep 0.1; done
git worktree list | grep -q 'pi-factory/bench/wt-hang' || fail "bench: no case worktree to interrupt" "$(cat "$work/bench-hang.log")"
kill -TERM -- "-$bpid" 2>/dev/null || true; wait "$bpid" 2>/dev/null || true
for _ in $(seq 50); do git worktree list | grep -q 'pi-factory/bench/wt-' || break; sleep 0.1; done
[ -z "$(git worktree list | grep 'pi-factory/bench/wt-')" ] && t "bench: an interrupted run removes its case worktree (trap, D101)" || fail "bench trap" "$(git worktree list; cat "$work/bench-hang.log")"
rm -f .factory/bench/results/hang.* .factory/bench/results/noguard.*
git add .factory/bench; git commit -qm "test: bench data"
unset BENCH_LOG FACTORY_BENCH_RUNNER

# D92: install once per machine (P11). Models per machine, then a project on the package.
echo "Context repos and investigation (D99)"
ctx="$work/ctx src"; git init -q "$ctx"; (cd "$ctx" && echo 'export const poll = () => 1;' > poll.js && git add -A && git commit -qm init)
mkdir -p .scratch/inv
inv_spec() {                                # <intent>
  printf '# Inv\n**Intent:** %s\n\nDuplicates appear after a sync.\n\n## Context repos\n- `%s` — pulls from the API every 5 minutes\n' "$1" "$ctx" > .scratch/inv/spec.md
}
inv_spec bugfix; git add .scratch/inv; git commit -qm "test: investigation mission"
istep() { head -1 <<<"$(bash scripts/factory/next.sh inv 2>&1 || true)"; }
[ "$(bash -c '. scripts/factory/lib.sh; context_repos .scratch/inv/spec.md' | cut -f1,4)" = "$(printf 'ctx src\tpulls from the API every 5 minutes')" ] \
  && t "the spec's context repos are parsed (name, role)" || fail "context parse" "$(bash -c '. scripts/factory/lib.sh; context_repos .scratch/inv/spec.md')"
[ "$(istep)" = "STEP: context-sync" ] && t "a bugfix naming context repos starts by syncing them" || fail "context-sync step" "$(bash scripts/factory/next.sh inv 2>&1)"
bash scripts/factory/context.sh sync inv >"$work/ctx.log" 2>&1 || fail "context sync" "$(cat "$work/ctx.log")"
cl=".factory/context/ctx src"
[ -f "$cl/poll.js" ] && [ "$(stat -c %A "$cl/poll.js" | grep -o w)" = "" ] && grep -q "$(git -C "$ctx" rev-parse HEAD)" .scratch/inv/context.tsv \
  && [ -z "$(git status --porcelain -- .factory/context)" ] \
  && t "context repos are cloned into the factory's folder, read-only on disk, recorded, invisible to git" || fail "context clone" "$(ls -la "$cl" 2>&1; cat .scratch/inv/context.tsv 2>&1; git status --porcelain)"
# D101: nothing is pushed from a clone; check compares source and branch, not names; "home" is reserved.
[ "$(git -C "$cl" remote get-url --push origin)" = no-push ] && t "a context clone's push URL is no-push (D101)" || fail "no-push" "$(git -C "$cl" remote -v)"
cp .scratch/inv/spec.md "$work/inv-spec.bak"
bash scripts/factory/context.sh check inv >/dev/null || fail "context check" "$(bash scripts/factory/context.sh check inv 2>&1)"
sed -i.bak "s|^- \`$ctx\`|- $ctx@other|" .scratch/inv/spec.md && rm -f .scratch/inv/spec.md.bak
out="$(bash scripts/factory/context.sh check inv 2>&1)" && fail "context check must see the new branch" "$out"
grep -q 'sync again' <<<"$out" && t "context check compares source and branch, not just names (D101)" || fail "context check branch" "$out"
printf '\n- ../home — a repo named like this project\n' >> .scratch/inv/spec.md
out="$(bash scripts/factory/context.sh check inv 2>&1)" && fail "home must be refused" "$out"
grep -q "can't be named 'home'" <<<"$out" && t "a context repo named home is refused (reserved, D101)" || fail "home reserved" "$out"
cp "$work/inv-spec.bak" .scratch/inv/spec.md
printf 'diff --git a/.factory/context/ctx src/poll.js b/.factory/context/ctx src/poll.js\n--- a/.factory/context/ctx src/poll.js\n+++ b/.factory/context/ctx src/poll.js\n@@ -1 +1 @@\n-export const poll = () => 1;\n+export const poll = () => 2;\n' > "$work/ctx.patch"
if bash scripts/factory/patch-guard.sh "$work/ctx.patch" >"$work/pg.log"; then fail "a patch into a context repo must be blocked"; fi
grep -q 'BLOCKED paths: .factory/context/ctx src/poll.js' "$work/pg.log" && t "the patch guard refuses a change in a context repo" || fail "ctx patch guard" "$(cat "$work/pg.log")"
[ "$(istep)" = "STEP: investigate" ] && t "then the investigation starts: briefs missing" || fail "investigate step" "$(bash scripts/factory/next.sh inv 2>&1)"
bash scripts/factory/workflow.sh investigate inv > "$work/wf.log" 2>&1 || fail "investigate wave" "$(cat "$work/wf.log")"
wf="$(sed -n 's/^WORKFLOW_FILE: //p' "$work/wf.log")"
grep -q '"key": "explore-ctx src"' "$wf" && grep -q '"key": "explore-home"' "$wf" && grep -q '"agent": "factory-investigator"' "$wf" \
  && [ "$(cat .scratch/inv/state/investigate.rounds)" = 1 ] && t "the investigate wave: one fresh explorer per repo, then the investigator (round 1)" || fail "investigate wave" "$(cat "$wf")"
bash scripts/factory/brief.sh explorer inv "ctx src" > "$work/b.txt"
grep -q 'Target: context repo ctx src at .factory/context/ctx src/ (pulls from the API every 5 minutes)' "$work/b.txt" && grep -q 'never run git in them' "$work/b.txt" \
  && t "an explorer's brief names its one repo and forbids changing it" || fail "explorer brief" "$(cat "$work/b.txt")"
mkdir -p .scratch/inv/context
echo "# ctx src" > ".scratch/inv/context/ctx src.md"; echo "# home" > .scratch/inv/context/home.md
printf '# Investigation: inv\n\n## System map\n- bot polls the API\n\n## Hypotheses\n- **H1** open: retries replay a sync\n\n## Questions\n- Q1 [ctx src]: does a failed poll retry with the same payload & key?\n' > .scratch/inv/investigation.md
[ "$(istep)" = "STEP: investigate" ] && grep -q 'answers to Q1' <<<"$(bash scripts/factory/next.sh inv)" && t "an open question sends the investigation round again" || fail "question loop" "$(bash scripts/factory/next.sh inv 2>&1)"
bash scripts/factory/brief.sh explorer inv Q1 > "$work/b.txt"
grep -qF 'answer Q1 about ctx src (.factory/context/ctx src/): does a failed poll retry with the same payload & key?' "$work/b.txt" \
  && t "a question goes to a fresh explorer in that repo, its text intact" || fail "question brief" "$(cat "$work/b.txt")"
mkdir -p .scratch/inv/context/answers; echo "Yes, same key (poll.js:1)" > .scratch/inv/context/answers/Q1.md
printf '\n## Conclusion\n**Cause:** a retried poll replays the sync.\n**Fix belongs:** here\n**Reproduction:** issues/01-reproduce-dup.md\n\n### Assertions for the fix\n- a sync replayed twice creates no duplicate\n' >> .scratch/inv/investigation.md
grep -q 'a reproduction ticket' <<<"$(bash scripts/factory/next.sh inv)" && t "a fix here needs its reproduction ticket first" || fail "repro needed" "$(bash scripts/factory/next.sh inv 2>&1)"
mkdir -p .scratch/inv/issues; printf '# 01-reproduce-dup\n**Test:** `tests/dup.test.js`\n## Covers: enabler\nA replayed sync duplicates.\n' > .scratch/inv/issues/01-reproduce-dup.md
[ "$(istep)" = "STEP: approve-conclusion" ] && t "the conclusion waits for the human" || fail "approve-conclusion" "$(bash scripts/factory/next.sh inv 2>&1)"
cp .scratch/inv/investigation.md "$work/inv.bak"; printf '\n**Conclusion approved:** %s\n' "$(date +%F)" >> .scratch/inv/investigation.md
[ "$(istep)" = "STEP: approve-conclusion" ] && grep -q 'no /factory-approve record' <<<"$(bash scripts/factory/next.sh inv)" \
  && t "a hand-written conclusion approval approves nothing (D101)" || fail "conclusion self-approval" "$(bash scripts/factory/next.sh inv 2>&1)"
cp "$work/inv.bak" .scratch/inv/investigation.md
bash scripts/factory/human.sh approve inv conclusion >/dev/null 2>&1 || fail "approve conclusion" "$(bash scripts/factory/human.sh approve inv conclusion 2>&1)"
grep -qE '^\*\*Conclusion approved:\*\* [0-9-]{10}' .scratch/inv/investigation.md && grep -q 'approve-conclusion' .scratch/inv/decisions.tsv \
  && [ "$(istep)" = "STEP: contract" ] && t "approved: the usual mission starts at the contract" || fail "after conclusion" "$(bash scripts/factory/next.sh inv 2>&1)"
touch .scratch/inv/state/01-reproduce-dup.integrated
bash -c '. scripts/factory/lib.sh; frozen_tests .scratch/inv/spec.md' | grep -qx 'tests/dup.test.js' && t "once integrated, the reproduction test is frozen (D93)" || fail "repro frozen" "$(bash -c '. scripts/factory/lib.sh; frozen_tests .scratch/inv/spec.md')"
rm -f .scratch/inv/state/01-reproduce-dup.integrated
sed -i.bak 's/^\*\*Fix belongs:\*\* here/**Fix belongs:** ctx src/' .scratch/inv/investigation.md && rm -f .scratch/inv/investigation.md.bak
grep -q 'the finding for ctx src' <<<"$(bash scripts/factory/next.sh inv)" && t "a fix elsewhere needs a finding for that team" || fail "finding needed" "$(bash scripts/factory/next.sh inv 2>&1)"
echo "Symptom, cause, evidence, suggested fix" > ".scratch/inv/finding-for-ctx src.md"
[ "$(istep)" = "STEP: handoff" ] && t "then the mission hands off and changes nothing here" || fail "handoff" "$(bash scripts/factory/next.sh inv 2>&1)"
sed -i.bak 's/^\*\*Fix belongs:\*\* ctx src/**Fix belongs:** here/' .scratch/inv/investigation.md && rm -f .scratch/inv/investigation.md.bak
inv_spec exploration
[ "$(istep)" = "STEP: report" ] && t "an exploration ends with its approved report" || fail "report" "$(bash scripts/factory/next.sh inv 2>&1)"
inv_spec bugfix; rm -f .scratch/inv/context/home.md; echo 3 > .scratch/inv/state/investigate.rounds
[ "$(istep)" = "STEP: escalate" ] && t "an investigation that used its rounds escalates to the human" || fail "rounds limit" "$(bash scripts/factory/next.sh inv 2>&1)"
bash scripts/factory/context.sh release inv >/dev/null
[ -n "$(stat -c %A "$cl/poll.js" | grep -o w)" ] && t "release gives write permission back" || fail "release" "$(ls -la "$cl")"
chmod -R u+w .factory/context; rm -rf .scratch/inv .factory/context
git add -A .scratch; git commit -qm "test: investigation done" >/dev/null 2>&1 || true

echo "Install once (D92)"
mkdir -p "$PI_CODING_AGENT_DIR"
printf '{"subagents":{"agentOverrides":{"factory-worker":{"model":"gw/maker-2","thinking":"low"}}}}' > "$PI_CODING_AGENT_DIR/settings.json"
[ "$(node scripts/factory/effective-models.mjs | awk -F'\t' '$1 == "factory-worker" { print $2 "@" $3 }')" = "gw/maker-2@low" ] \
  && [ "$(bash -c '. scripts/factory/lib.sh; agent_model factory-worker')" = gw/maker-2 ] \
  && t "a user agentOverride sets the model this machine runs, even on copied agents" || fail "user override" "$(node scripts/factory/effective-models.mjs)"
cp .pi/settings.json "$work/settings.keep"
node -e 'const f=".pi/settings.json",s=require("./"+f);s.subagents.agentOverrides={"factory-worker":{model:"gw/maker-3"}};require("fs").writeFileSync(f,JSON.stringify(s))'
[ "$(bash -c '. scripts/factory/lib.sh; agent_model factory-worker')" = gw/maker-3 ] && t "a project agentOverride wins over the user's, as in pi-subagents" || fail "project override"
cp "$work/settings.keep" .pi/settings.json; rm -f "$PI_CODING_AGENT_DIR/settings.json"
[ "$(node -p 'require(process.argv[1]).version' "$root/package.json")" = "$(cat "$root/.factory/VERSION")" ] \
  && node -e 'const p=require(process.argv[1]),fs=require("fs"),path=require("path");const all=[...p.pi.extensions,...p.pi.prompts,...p.pi.skills,...p.pi.subagents.agents];process.exit(all.every(x=>fs.existsSync(path.join(path.dirname(process.argv[1]),x)))?0:1)' "$root/package.json" \
  && t "package.json: the version of .factory/VERSION; every Pi resource it declares exists" || fail "package manifest"

pk="$work/pkg repo"; mkdir -p "$pk/apps/svc"; git -C "$pk" init -q
( cd "$pk"; echo root > README.md; mkdir -p apps/svc/src; echo 'export const s = 1;' > apps/svc/src/s.js; printf 'coverage' > apps/svc/.gitignore; git add -A; git commit -qm init )
cd "$pk/apps/svc"
bash "$root/scripts/factory/onboard.sh" >"$work/onboard.log" 2>&1 || fail "onboard" "$(cat "$work/onboard.log")"
changed="$(git status --porcelain --untracked-files=all -- . | awk '{ print $2 }' | sed 's#^apps/svc/##' | sort | tr '\n' ' ')"
case "$changed" in *scripts/*|*.pi/agents*|*.pi/skills*|*briefs*|*docs/agents/factory.md*) fail "onboard must not add factory files" "$changed" ;; esac
for f in .factory/commands.env .factory/VERSION .factory/ci/factory.gitlab-ci.yml docs/agents/quality-bar.md GLOSSARY.md AGENTS.md .pi/settings.json; do
  grep -q "$f" <<<"$changed" || fail "onboard: $f missing" "$changed"
done
t "onboard writes only the project's own files ($(wc -w <<<"$changed" | tr -d ' ') files)"
bash "$root/scripts/factory/onboard.sh" --no-setup >"$work/onboard2.log" 2>&1 || fail "onboard again" "$(cat "$work/onboard2.log")"
[ "$(grep -cx 'instrument/results/' .gitignore)" = 1 ] && grep -qx coverage .gitignore \
  && t "onboard twice: a .gitignore without a final newline keeps its last line, nothing appended twice" || fail "gitignore append" "$(cat -A .gitignore)"

[ "$(readlink scripts/factory)" = "$root/scripts/factory" ] && [ "$(readlink docs/agents/factory.md)" = "$root/docs/agents/factory.md" ] \
  && grep -qx '/apps/svc/scripts/factory' "$pk/.git/info/exclude" && bash scripts/factory/link.sh --check >/dev/null \
  && t "factory scripts, briefs and docs are local links, excluded from git (monorepo folder)" || fail "links" "$(ls -la scripts; cat "$pk/.git/info/exclude")"
[ "$(cat .factory/VERSION)" = "$(cat "$root/.factory/VERSION")" ] && ! grep -q '<' .pi/settings.json \
  && [ "$(cat .factory/package-sha)" = "$(git -C "$root" rev-parse HEAD)" ] \
  && [ "$(grep -c 'scripts/factory/link.sh' .factory/ci/factory.gitlab-ci.yml)" = 3 ] && grep -q 'models-lint.mjs --per-machine-ok' .factory/ci/factory.gitlab-ci.yml \
  && grep -q 'cd "apps/svc"' .factory/ci/factory.gitlab-ci.yml && ! grep -qE 'FACTORY_PACKAGE_GIT: *"?http' .factory/ci/factory.gitlab-ci.yml \
  && t "project expects this factory version and commit; CI has no default fetch URL; no placeholder model scope" || fail "onboard files" "$(cat .pi/settings.json .factory/ci/factory.gitlab-ci.yml)"
# The CI fetch line, run as a job would: a fresh checkout without the links.
fetch="$(grep -m1 "^    - 'test -e scripts/factory" .factory/ci/factory.gitlab-ci.yml | sed "s/^    - '//; s/'\$//")"
git -C "$pk" add -A; git -C "$pk" commit -qm onboard
rm -rf "$work/ci"; git clone -q "$pk" "$work/ci"
out="$(cd "$work/ci/apps/svc" && bash -c "$fetch" 2>&1)" && fail "CI fetch must refuse without FACTORY_PACKAGE_GIT"
grep -q 'FACTORY_PACKAGE_GIT is not set' <<<"$out" || fail "CI fetch message" "$out"
echo 0000000000000000000000000000000000000000 > "$work/ci/apps/svc/.factory/package-sha"
(cd "$work/ci/apps/svc" && FACTORY_PACKAGE_GIT="$root" bash -c "$fetch" >/dev/null 2>&1) && fail "CI fetch must refuse a commit it can't check out"
git -C "$work/ci" checkout -q -- .
(cd "$work/ci/apps/svc" && FACTORY_PACKAGE_GIT="$root" bash -c "$fetch" >/dev/null 2>&1) && [ -L "$work/ci/apps/svc/scripts/factory" ] \
  && [ "$(git -C "$(cd -P "$work/ci/apps/svc/scripts/factory/../.." && pwd)" rev-parse HEAD)" = "$(git -C "$root" rev-parse HEAD)" ] \
  && t "CI fetches the factory from FACTORY_PACKAGE_GIT at the recorded commit, into a directory of its own, then links it" || fail "CI fetch" "$(ls -la "$work/ci/apps/svc/scripts" 2>&1)"
[ "$(node scripts/factory/effective-models.mjs | wc -l | tr -d ' ')" = "$(ls "$root"/.pi/agents/factory/*.md | wc -l | tr -d ' ')" ] && node scripts/factory/models-lint.mjs --per-machine-ok >/dev/null \
  && t "agents come from the package; CI accepts models set per machine" || fail "package agents" "$(node scripts/factory/effective-models.mjs; node scripts/factory/models-lint.mjs --per-machine-ok)"
cp .pi/settings.json "$work/svc-settings"; node -e 'const f=".pi/settings.json",s=require("./"+f);s.subagents.disableBuiltins=false;require("fs").writeFileSync(f,JSON.stringify(s))'
out="$(node scripts/factory/models-lint.mjs --per-machine-ok 2>&1)" && fail "per-machine lint must still check the settings" "$out"
grep -q 'disableBuiltins must be true' <<<"$out" && t "per-machine lint skips only the model checks: settings still checked" || fail "per-machine lint" "$out"
cp "$work/svc-settings" .pi/settings.json
printf '{"subagents":{"agentOverrides":{"factory-worker":{"model":"gw/x"}}}}' > "$work/ov.json"
node scripts/factory/project-files.cjs settings "$root/.pi/settings.json" "$work/ov.json" "" >/dev/null
node -e 'process.exit(require(process.argv[1]).subagents.agentOverrides["factory-worker"].model==="gw/x"?0:1)' "$work/ov.json" \
  && t "a project's factory-* agentOverrides are kept (pi-subagents 0.76.1 applies them)" || fail "overrides kept" "$(cat "$work/ov.json")"
printf '{"agents":{"factory-worker":{"model":"gw/maker-1","thinking":"medium"},"factory-reviewer":{"model":"gw/judge-1"}},"allow":["gw/*"]}' > "$work/profile.json"
bash "$root/scripts/factory/factory.sh" models apply --user "$work/profile.json" >/dev/null
node -e 'const s=require(process.argv[1]).subagents;process.exit(s.agentOverrides["factory-worker"].model==="gw/maker-1"&&s.modelScope.allow[0]==="gw/*"?0:1)' "$PI_CODING_AGENT_DIR/settings.json" \
  && [ "$(node scripts/factory/effective-models.mjs | awk -F'\t' '$1 == "factory-reviewer" { print $2 }')" = gw/judge-1 ] \
  && t "factory models apply --user: this machine's models, for every project" || fail "apply --user" "$(cat "$PI_CODING_AGENT_DIR/settings.json")"
rm -f "$PI_CODING_AGENT_DIR/settings.json"
bash "$root/scripts/factory/factory.sh" version | grep -q "project expects: $(cat "$root/.factory/VERSION")" && t "factory version: installed and expected" || fail "factory version"
echo 99.0.0 > .factory/VERSION
bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1 || true
grep -q 'older than this project expects (99.0.0)' "$work/pre.log" && grep -q 'linked to the factory package' "$work/pre.log" \
  && t "pre-flight: an installed factory older than the project expects is refused; links checked" || fail "version check" "$(cat "$work/pre.log")"
printf '%s\n' "$(cat "$root/.factory/VERSION")" > .factory/VERSION
git -C "$pk" worktree add -q "$work/pk-wt" -b wt-test
printf '{"repoRoot":"%s","worktreePath":"%s","agentCwd":"%s","index":0}' "$pk" "$work/pk-wt" "$work/pk-wt/apps/svc" \
  | FACTORY_PROJECT_PREFIX=apps/svc node scripts/factory/worktree-hook.mjs > "$work/hook.json"
[ -L "$work/pk-wt/apps/svc/scripts/factory" ] && grep -q '"apps/svc/scripts/factory"' "$work/hook.json" && [ -z "$(git -C "$work/pk-wt" status --porcelain)" ] \
  && t "worker worktrees get the same links, kept out of the patch" || fail "worktree links" "$(cat "$work/hook.json"; git -C "$work/pk-wt" status --porcelain)"
git -C "$pk" worktree remove --force "$work/pk-wt"

mg="$work/migrate repo"; mkdir -p "$mg"; git -C "$mg" init -q; ( cd "$mg"; echo x > README.md; git add -A; git commit -qm init )
bash "$root/scripts/factory/install-into.sh" "$mg" --no-branch >/dev/null 2>&1; ( cd "$mg"; echo 'FACTORY_TEST_CMD="true"' >> .factory/commands.env; git add -A; git commit -qm "copied install" )
cd "$mg"
out="$(bash "$root/scripts/factory/onboard.sh" 2>&1)" && fail "onboard must refuse a copied install without --migrate"
grep -q -- '--migrate' <<<"$out" || fail "onboard copied message" "$out"
bash "$root/scripts/factory/onboard.sh" --migrate >"$work/migrate.log" 2>&1 || fail "migrate" "$(cat "$work/migrate.log")"
[ -z "$(git ls-files -- scripts/factory .pi/agents/factory .factory/briefs docs/factory)" ] && [ -L scripts/factory ] \
  && grep -q 'FACTORY_TEST_CMD="true"' .factory/commands.env && [ -f .pi/settings.json ] \
  && t "onboard --migrate removes the copied factory, keeps the project's own files, links the package" || fail "migrate result" "$(git status --short | head -20)"
cd "$repo"

echo "Vendored skills"
( cd "$root/.pi/skills/deepen-prompt" && sed -n '/^```$/,/^```$/p' SOURCE.md | grep -v '^```' | if command -v sha256sum >/dev/null; then sha256sum -c --quiet -; else shasum -a 256 -c --quiet -; fi ) >"$work/vendor.log" 2>&1 \
  && t "deepen-prompt is vendored unchanged (hashes in its SOURCE.md)" || fail "deepen-prompt changed: update SOURCE.md on purpose, or restore the files" "$(cat "$work/vendor.log")"

echo "Setup by rehearsal (D102)"
# head missing from the image: lib.sh's stand-in covers what the scripts call.
nohead="$work/nohead"; mkdir -p "$nohead"
for c in bash sh env sed awk grep cut tr wc sort uniq mktemp find xargs diff cat tail dirname basename git node ls rm mkdir cp mv ln printf readlink sha256sum shasum seq; do
  p="$(command -v "$c" 2>/dev/null || true)"; [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$nohead/$c"
done
out="$(PATH="$nohead" "$nohead/bash" -c '. "'"$root"'/scripts/factory/lib.sh"; command -v head >/dev/null && [ "$(type -t head)" = function ] || exit 9
  printf "a\nb\nc\n" | head -1; printf "1\n2\n3\n4\n5\n" | head -40 | wc -l | tr -d " "; printf "%s\n" x y | head -n 1
  printf "abcdef0123456789\n" > "'"$work"'/h"; head -c 12 "'"$work"'/h"; echo; set -o pipefail; seq 1 100000 2>/dev/null | head -1 >/dev/null; echo "pipe=$?"' 2>&1)"
[ "$out" = "$(printf 'a\n5\nx\nabcdef012345\npipe=0')" ] && t "no head on the machine: lib.sh's stand-in answers -N, -n N, -c N and files, and never breaks a pipe" || fail "head fallback" "$out"
rm -f "$nohead/diff"
out="$(PATH="$nohead" "$nohead/node" "$root/scripts/factory/env-check.mjs" 2>&1 || true)"
grep -q 'missing on this machine: diff' <<<"$out" && grep -q 'head is missing: the factory uses its own stand-in' <<<"$out" \
  && t "env-check names the commands the scripts need that this machine lacks" || fail "env-check tools" "$out"

# The factory as a folder of another repository (an internal mirror, D102).
mirror="$work/mirror"; mkdir -p "$mirror/pi-factory"; git -C "$mirror" init -q
( cd "$root" && git ls-files -co --exclude-standard -z | xargs -0 -I{} cp --parents {} "$mirror/pi-factory/" 2>/dev/null || true )
( cd "$mirror" && echo other > OTHER.md && git add -A && git commit -qm mirror )
mp="$work/mirror project"; mkdir -p "$mp"; git -C "$mp" init -q; ( cd "$mp"; echo x > README.md; git add -A; git commit -qm init )
cd "$mp"
bash "$mirror/pi-factory/scripts/factory/onboard.sh" --no-setup >"$work/onboard-mirror.log" 2>&1 || fail "onboard from a mirror" "$(cat "$work/onboard-mirror.log")"
[ "$(cat .factory/package-dir)" = pi-factory ] && [ "$(cat .factory/package-sha)" = "$(git -C "$mirror" rev-parse HEAD)" ] \
  && grep -q 'no model on this machine for factory-' "$work/onboard-mirror.log" \
  && t "onboard from a mirror: records the factory's folder next to the commit, and names the agents without a model" || fail "package-dir" "$(cat "$work/onboard-mirror.log")"
bash scripts/factory/skills-pin.sh verify >"$work/pin.log" 2>&1 && t "skills pin verifies on the installed package (paths relative, D102)" || fail "skills pin in package mode" "$(cat "$work/pin.log")"
fetch="$(grep -m1 "^    - 'test -e scripts/factory" .factory/ci/factory.gitlab-ci.yml | sed "s/^    - '//; s/'\$//")"
git add -A; git commit -qm onboard
rm -rf "$work/ci-mirror"; git clone -q "$mp" "$work/ci-mirror"
(cd "$work/ci-mirror" && FACTORY_PACKAGE_GIT="$mirror" bash -c "$fetch" >"$work/fetch.log" 2>&1) && [ -L "$work/ci-mirror/scripts/factory" ] \
  && [ -f "$work/ci-mirror/scripts/factory/next.sh" ] && t "CI links the factory's folder of the mirror clone" || fail "CI fetch from a mirror" "$(cat "$work/fetch.log"; ls -la "$work/ci-mirror/scripts" 2>&1)"
echo ../x > "$work/ci-mirror/.factory/package-dir"; rm -rf "$work/ci-mirror/scripts"
(cd "$work/ci-mirror" && FACTORY_PACKAGE_GIT="$mirror" bash -c "$fetch" >"$work/fetch.log" 2>&1) && fail "CI must refuse a package-dir outside the repository"
grep -q 'package-dir must be a folder inside' "$work/fetch.log" && t "CI refuses a package-dir that leaves the factory repository" || fail "package-dir check" "$(cat "$work/fetch.log")"

# The probe goes where the runner looks: jest's testMatch (api-toolbox, no tests
# yet), else the project's own naming (spec or test).
pm="$work/probe-match"; mkdir -p "$pm/src" "$pm/node_modules/.bin"; cd "$pm"; git init -q
printf '{"name":"p","private":true,"scripts":{"test":"jest --coverage"},"devDependencies":{"jest":"0.0.0","ts-jest":"0.0.0"}}\n' > package.json
printf 'export default {\n  preset: "ts-jest",\n  testMatch: ["**/test/**/*.spec.ts"],\n};\n' > jest.config.ts
echo '{}' > tsconfig.json; echo 'export const a = 1;' > src/a.ts; printf 'node_modules\n' > .gitignore
printf '#!/bin/sh\nexit 0\n' > node_modules/.bin/jest; chmod +x node_modules/.bin/jest
git add -A; git commit -qm init
f1="$(node "$root/scripts/factory/setup-discover.mjs" | node -e 'let s="";process.stdin.on("data",(c)=>s+=c).on("end",()=>console.log(JSON.parse(s).probe.file))')"
sed -i 's|testMatch: \[.*\],|roots: ["<rootDir>/src"],|' jest.config.ts; mkdir -p src/x; echo 'it("a",()=>{});' > src/x/a.spec.ts; git add -A; git commit -qm spec
f2="$(node "$root/scripts/factory/setup-discover.mjs" | node -e 'let s="";process.stdin.on("data",(c)=>s+=c).on("end",()=>console.log(JSON.parse(s).probe.file))')"
[ "$f1" = "test/factory-setup-probe.spec.ts" ] && [ "$f2" = "src/x/factory-setup-probe.spec.ts" ] \
  && t "discover: the probe follows jest's testMatch, else the project's spec/test naming" || fail "probe placement" "testMatch → $f1; spec files → $f2"
cd "$root"

# A Node project: a stand-in runner (node_modules/.bin/jest), one passing test.
sp="$work/setup project"; mkdir -p "$sp/tests" "$sp/node_modules/.bin"; cd "$sp"; git init -q
printf '{"name":"s","private":true,"scripts":{"test":"jest","postinstall":"npm audit fix"},"devDependencies":{"jest":"0.0.0"}}\n' > package.json
cat > node_modules/.bin/jest <<'JEST'
#!/usr/bin/env node
const fs = require("fs"), path = require("path"), { spawnSync } = require("child_process");
const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const walk = (d) => fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]) : [];
const files = args.length ? args : walk("tests").filter((f) => /\.test\.js$/.test(f));
if (!files.length) { console.log("No tests found, exiting with code 0"); process.exit(0); }
let bad = 0;
for (const f of files) { const r = spawnSync(process.execPath, [f], { encoding: "utf8" }); if (r.status) { bad++; console.log(`FAIL ${f}\n${r.stderr}`); } else console.log(`PASS ${f}`); }
process.exit(bad ? 1 : 0);
JEST
chmod +x node_modules/.bin/jest
echo 'require("assert").strictEqual(1 + 1, 2);' > tests/add.test.js
printf 'node_modules\n' > .gitignore; echo 'TOKEN=x' > .env
printf 'deploy-dev:\n  stage: deploy\n  script:\n    - ./deploy.sh\n  rules:\n    - if: $CI_COMMIT_BRANCH != "production" && $CI_PIPELINE_SOURCE != "merge_request_event"\n' > .gitlab-ci.yml
mkdir -p .factory; printf 'FACTORY_LINT_CMD=""\nFACTORY_TEST_CMD=""\nFACTORY_TEST_FILES_CMD=""\nFACTORY_EXTRA_CMD=""\n' > .factory/commands.env
git add -A; git commit -qm init
disc="$(node "$root/scripts/factory/setup-discover.mjs")"
node -e 'const d=JSON.parse(process.argv[1]);const t=(f)=>d.findings.some(f);process.exit(
  d.candidates.test[0].cmd==="node_modules/.bin/jest --passWithNoTests" && d.probe.file==="tests/factory-setup-probe.test.js"
  && t((f)=>f.level==="decide"&&/postinstall: npm audit fix/.test(f.text)) && t((f)=>/tracked environment files: \.env/.test(f.text))
  && t((f)=>f.level==="decide"&&/job `deploy-dev`/.test(f.text)) ? 0 : 1)' "$disc" \
  && t "discover: the local runner first; install scripts that write, tracked .env files and jobs a branch push deploys are named" || fail "discover" "$disc"
out="$(node "$root/scripts/factory/setup.mjs" --write 2>&1)" || true
grep -q '✓ FACTORY_TEST_CMD  node_modules/.bin/jest --passWithNoTests' <<<"$out" && grep -q 'turns it red, because of that file' .factory/setup.md \
  && grep -q '✓ FACTORY_TEST_FILES_CMD' <<<"$out" && grep -q '^FACTORY_TEST_CMD="node_modules/.bin/jest --passWithNoTests"$' .factory/commands.env \
  && grep -q '^FACTORY_TEST_FILES_CMD="node_modules/.bin/jest --passWithNoTests {files}"$' .factory/commands.env \
  && [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] && [ ! -e tests/factory-setup-probe.test.js ] \
  && t "setup: green twice offline, red with a planted failing file, files command narrowed to it; written; no worktree or probe left" || fail "setup rehearsal" "$out"$'\n'"$(cat .factory/setup.md)"
printf 'FACTORY_TEST_CMD="true"\n' > .factory/commands.env
out="$(node "$root/scripts/factory/setup.mjs" --write 2>&1)" && fail "setup must fail a test command that ignores a failing test" "$out"
grep -q 'leaves it green' <<<"$out" && grep -qx 'FACTORY_TEST_CMD="true"' .factory/commands.env \
  && t "setup: a command a failing test can't turn red fails; your own value is never replaced" || fail "setup yours" "$out"
printf 'FACTORY_TEST_CMD="npx some-runner-not-here"\n' > .factory/commands.env
out="$(node "$root/scripts/factory/setup.mjs" 2>&1)" || true
grep -q "isn't installed in the project: npx would download it" <<<"$out" && t "setup: a command npx would download fails (a worker is offline)" || fail "setup npx" "$out"
echo 'process.exit(process.env.MY_API_TOKEN ? 3 : process.env.HTTPS_PROXY === "http://127.0.0.1:9" && process.env.npm_config_offline === "true" ? 0 : 4);' > check-env.js
git add check-env.js; git commit -qm "env check"
printf 'FACTORY_TEST_CMD="node check-env.js"\n' > .factory/commands.env
out="$(MY_API_TOKEN=s3cr3t node "$root/scripts/factory/setup.mjs" 2>&1)" || true
grep -q 'green twice offline, credentials unset' .factory/setup.md && t "setup rehearses with credential variables unset, package managers offline and the proxies on a closed port" || fail "setup env" "$out"$'\n'"$(cat .factory/setup.md)"

# Review fixes: verdicts from exit codes, process groups, quoting, the user's .git untouched.
echo 'console.log("getaddrinfo ENOTFOUND api.example.invalid (handled)");' > net-ok.js
echo 'process.exit(require("fs").existsSync("café new.txt") ? 0 : 5);' > new-file.js
printf 'console.error("Oops! Something went wrong! couldn'"'"'t find the plugin"); process.exit(2);\n' > lint-crash.js
git add net-ok.js new-file.js lint-crash.js; git commit -qm "review fixtures"
echo x > "café new.txt"
printf 'FACTORY_TEST_CMD="node net-ok.js && node new-file.js"\nFACTORY_LINT_CMD="node lint-crash.js"\n' > .factory/commands.env
out="$(node "$root/scripts/factory/setup.mjs" 2>&1)" || true
grep -q 'green twice offline' .factory/setup.md && ! grep -q 'reaching for the network' .factory/setup.md \
  && grep -q "didn't run to the end (exit 2" .factory/setup.md && ! grep -q 'leaves files in the tree' .factory/setup.md \
  && ! grep -q 'no test command found' .factory/setup.md && ! grep -q 'worktreeConfig' .git/config \
  && t "setup: a passing suite that logs a network error passes; a crashing lint fails; new files with unusual names are rehearsed; .git/config untouched" || fail "review fixes" "$out"$'\n'"$(cat .factory/setup.md)"
rm -f "café new.txt"
printf 'FACTORY_TEST_CMD="sleep 41.37; true"\n' > .factory/commands.env
out="$(node "$root/scripts/factory/setup.mjs" --timeout 1 2>&1)" || true
sleep 1
grep -q 'timed out after 1s' .factory/setup.md && ! pgrep -f '^sleep 41[.]37' >/dev/null && [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] \
  && t "setup: a command that times out is stopped with everything it started" || fail "setup timeout" "$out"$'\n'"$(pgrep -fa '^sleep 41[.]37')"

# This machine: floating aliases, production routes, TLS checks off.
mkdir -p "$PI_CODING_AGENT_DIR"
printf '{"providers":{"gw":{"baseUrl":"https://llm-prod.example/v1","api":"openai-completions","apiKey":"GW_KEY"}}}' > "$PI_CODING_AGENT_DIR/models.json"
printf '{"subagents":{"agentOverrides":{"factory-reviewer":{"model":"gw/judge-latest"},"factory-worker":{"model":"gw/maker-1"}}}}' > "$PI_CODING_AGENT_DIR/settings.json"
out="$(NODE_TLS_REJECT_UNAUTHORIZED=0 node "$root/scripts/factory/env-check.mjs" 2>&1 || true)"
grep -q 'gw/judge-latest is a floating alias (factory-reviewer)' <<<"$out" && grep -q 'factory-reviewer, factory-worker go through llm-prod.example, which looks like production' <<<"$out" \
  && grep -q 'NODE_TLS_REJECT_UNAUTHORIZED=0' <<<"$out" && t "env-check: floating aliases, roles on a production-looking route, TLS checks off" || fail "env-check" "$out"
out="$(FACTORY_GATEWAY_PROD_RE='nothing-matches' node "$root/scripts/factory/env-check.mjs" 2>&1 || true)"
grep -q 'no factory agent on a production route' <<<"$out" && t "env-check: FACTORY_GATEWAY_PROD_RE makes the route check exact" || fail "env-check prod re" "$out"
printf 'FACTORY_TEST_CMD="node_modules/.bin/jest"\nFACTORY_EXTRA_CMD="curl -H \\"Authorization: Bearer abcdefghijklmnop1234\\" https://x"\n' > .factory/commands.env
out="$(node "$root/scripts/factory/report.mjs" --full 2>&1)"
grep -q '^factory report ' <<<"$out" && grep -q 'reviewer: gw/judge-latest' <<<"$out" && grep -q 'floating alias' <<<"$out" && grep -q '^Commands' <<<"$out" \
  && ! grep -q abcdefghijklmnop1234 <<<"$out" && grep -q REDACTED <<<"$out" && [ -f "$(git rev-parse --git-common-dir)/pi-factory/report.txt" ] \
  && t "factory report: one redacted text (models and routes, commands, setup, pre-flight), kept out of the repository" || fail "report" "$out"
rm -f "$PI_CODING_AGENT_DIR/models.json" "$PI_CODING_AGENT_DIR/settings.json"
cd "$repo"

if [ -n "${mono:-}" ]; then
  [ "$(cat "$mono/projects/other/keep.js")" = keep ] && [ -z "$(git -C "$mono" log --format=%H -- projects/other README.md | awk 'NR > 1')" ] \
    && t "monorepo: a whole mission never touched the sibling project or the root" || fail "monorepo leak" "$(git -C "$mono" log --stat -- projects/other README.md)"
fi

echo; echo "ALL $pass CHECKS PASSED"
