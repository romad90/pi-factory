#!/usr/bin/env bash
# End-to-end test of the factory scripts, without any model: installs the
# factory into a throwaway repo, then plays a mission by writing the files
# agents would write, and checks every STEP, gate and record on the way.
#
# Usage: bash tests/factory.test.sh        (needs bash, git, node)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export FACTORY_NOTIFY=0 GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t
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
[ -f docs/agents/contract-checklist-api.md ] && [ -f docs/agents/quality-bar-batch.md ] && [ ! -f docs/agents/contract-checklist-bots.md ] \
  && t "only the requested practice packs are installed" || fail "packs" "$(ls docs/agents)"
grep -q 'every docs/agents/quality-bar-\*.md' .factory/briefs/code-steward.md && t "the steward brief reads the packs' quality bars" || fail "steward pack brief"
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
  && t "a monorepo project installs into its folder only" || fail "monorepo install scope" "$(cat "$work/install3.log"; git -C "$repo2" show --stat HEAD)"
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

echo 'export const hello = () => "hello";' > src/tools/hello.js
git add -N src/tools/hello.js; git diff -- src > "$work/01.patch"; git rm -q --cached src/tools/hello.js; rm src/tools/hello.js
bash scripts/factory/integrate.sh demo 01-hello "$work/01.patch" >"$work/int.log" 2>&1 || fail "integrate 01" "$(cat "$work/int.log")"
c1="$(cat $m/state/01-hello.integrated)"
grep -q '^feat(demo): 01-hello' <<<"$(git log -1 --skip=1 --format=%s)" && t "integration commit is a Conventional Commit" || fail "integration message: $(git log -3 --format=%s)"
expect_step review "integrated ticket waits for review"

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

# Ticket 02 asks a decision.
bash scripts/factory/human.sh ask demo 02-count "Delete old counts in production? A) yes B) no" >/dev/null
expect_step decide "open question stops the mission"
bash scripts/factory/human.sh decide demo B "keep data, irreversible" >/dev/null
grep -q $'02-count\tdecide\tDelete old counts' $m/decisions.tsv && t "/factory-decide logs question and answer" || fail "decide log" "$(cat $m/decisions.tsv)"
expect_step build "answered, ticket 02 builds"
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
bash scripts/factory/metrics.sh demo > "$work/metrics.md"
grep -q 'First-pass review rate | 0% (0/2)' "$work/metrics.md" && t "metrics: first pass from history (no ticket passed its first round)" || fail "metrics first pass" "$(cat "$work/metrics.md")"
grep -q '(3)' "$work/metrics.md" && grep -q 'patch guard | 1' "$work/metrics.md" && t "metrics: deterministic fails and guard blocks counted" || fail "metrics det" "$(cat "$work/metrics.md")"

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

echo "Pre-flight"
bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1 && t "pre-flight OK on a configured repo" || fail "preflight" "$(cat "$work/pre.log")"
echo dirty >> src/tools/a.js
if bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1; then fail "dirty tree must fail pre-flight"; fi
t "pre-flight fails on a dirty tree"
git checkout -q -- src/tools/a.js

if [ -n "${mono:-}" ]; then
  [ "$(cat "$mono/projects/other/keep.js")" = keep ] && [ -z "$(git -C "$mono" log --format=%H -- projects/other README.md | awk 'NR > 1')" ] \
    && t "monorepo: a whole mission never touched the sibling project or the root" || fail "monorepo leak" "$(git -C "$mono" log --stat -- projects/other README.md)"
fi

echo; echo "ALL $pass CHECKS PASSED"
