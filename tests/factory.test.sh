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
repo="$work/bot repo & co"; mkdir -p "$repo"; cd "$repo"
git init -q; mkdir -p src/tools; echo 'export const a = 1;' > src/tools/a.js; echo 'x' > README.md
git add -A; git commit -q -m init
bash "$root/scripts/factory/install-into.sh" "$repo" >"$work/install.log" 2>&1 || fail "install-into.sh" "$(cat "$work/install.log")"
[ "$(git branch --show-current)" = "chore/install-pi-factory-$(cat "$root/.factory/VERSION")" ] && t "install lands on its own branch" || fail "install branch"
[ -z "$(git status --porcelain)" ] && git log -1 --format=%s | grep -q '^chore(factory): install' && t "install is one commit" || fail "install commit"
[ -f .factory/ci/factory.gitlab-ci.yml ] && [ -f docs/factory/CHEATSHEET.md ] && t "CI template and cheat sheet installed" || fail "CI template"

# Fake models: author/worker one family, critic/judges another.
for a in .pi/agents/factory/*.md; do
  case "$(basename "$a")" in
    factory-contract-critic.md|factory-reviewer.md|factory-review-axis.md|factory-validator.md) m=gw/judge-1 ;;
    *) m=gw/maker-1 ;;
  esac
  sed -i.bak "s|^model: .*|model: $m|" "$a" && rm -f "$a.bak"
done
node -e '
const fs=require("fs"); const f=".factory/model-families.json"; const j=JSON.parse(fs.readFileSync(f,"utf8"));
j.families.push({match:"*maker*",family:"makers"},{match:"*judge*",family:"judges"}); fs.writeFileSync(f, JSON.stringify(j,null,2));
const s=".pi/settings.json"; const k=JSON.parse(fs.readFileSync(s,"utf8")); k.subagents.modelScope.allow=["gw/*"]; fs.writeFileSync(s, JSON.stringify(k,null,2));'
node scripts/factory/models-lint.mjs >"$work/lint.log" 2>&1 && t "models-lint passes with separated families" || fail "models-lint" "$(cat "$work/lint.log")"
git add -A; git commit -q -m "chore: models"; base0="$(git rev-parse HEAD)"

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
cat > $m/issues/01-hello.md <<'TK'
# 01 hello
## Covers
VAL-HELLO-001
TK
cat > $m/issues/02-count.md <<'TK'
# 02 count
## Covers
VAL-HELLO-002
## Blocked by
01
TK
bash scripts/factory/checkpoint.sh demo >/dev/null
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
git log -1 --skip=1 --format=%s | grep -q '^feat(demo): 01-hello' && t "integration commit is a Conventional Commit" || fail "integration message: $(git log -3 --format=%s)"
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
expect_step pr "accepted by a human"
gate_ok "gate passes the whole mission"
bash scripts/factory/metrics.sh demo > "$work/metrics.md"
grep -q 'First-pass review rate | 50% (1/2)' "$work/metrics.md" && t "metrics: first pass from history (ticket 01 is not a first pass)" || fail "metrics first pass" "$(cat "$work/metrics.md")"
grep -q '(2)' "$work/metrics.md" && t "metrics: deterministic fails counted" || fail "metrics det"

echo "Staleness and pause"
echo '# docs' >> README.md; git commit -q -am "docs: readme"
expect_step pr "docs change keeps the behavior verdict fresh"
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

echo "Pre-flight"
bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1 && t "pre-flight OK on a configured repo" || fail "preflight" "$(cat "$work/pre.log")"
echo dirty >> src/tools/a.js
if bash scripts/factory/doctor.sh --quick >"$work/pre.log" 2>&1; then fail "dirty tree must fail pre-flight"; fi
t "pre-flight fails on a dirty tree"
git checkout -q -- src/tools/a.js

echo; echo "ALL $pass CHECKS PASSED"
