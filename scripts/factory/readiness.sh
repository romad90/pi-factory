#!/usr/bin/env bash
# Step 2 readiness for this repo (D28). Inspired by Factory's agent-readiness
# pillars, cut down to what this factory needs. Each failing check names
# its fix. Advisory by default; --strict exits 1 on any failure.
#
# Usage: scripts/factory/readiness.sh [--strict]
# Helpers are called indirectly through check():
# shellcheck disable=SC2329
true
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

strict=0; [ "${1:-}" = "--strict" ] && strict=1
pass=0; total=0

section() { printf '\n%s\n' "$1"; }
check() {                                   # <description> <fix> <command...>
  local desc="$1" fix="$2"; shift 2
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1)); printf '  ✓ %s\n' "$desc"
  else
    printf '  ✗ %s\n      fix: %s\n' "$desc" "$fix"
  fi
}
has_line()   { grep -qE "$1" "$2"; }
no_line()    { ! grep -qE "$1" "$2"; }
nonempty()   { grep -qvE '^[[:space:]]*(#|$)' "$1"; }
any_file()   { compgen -G "$1" >/dev/null; }

ci=.gitlab-ci.yml

section "Context"
check "AGENTS.md exists" "write the general AGENTS.md" test -f AGENTS.md
check "AGENTS.md has the factory section" "paste AGENTS.factory.md into it" has_line '^## Agentic factory' AGENTS.md
check "GLOSSARY.md exists" "run /grill-with-docs or /domain-modeling" test -f GLOSSARY.md
check "no leftover CONTEXT.md" "rename CONTEXT.md to GLOSSARY.md (v1.3)" test ! -f CONTEXT.md

section "Skills and agents"
check "pinned skills v1.3.1 verified" "run scripts/factory/skills-pin.sh verify and fix what it lists" bash "$here/skills-pin.sh" verify
check "local skills present" "copy contract, contract-critic, verify-behavior into $FACTORY_SKILLS_DIR" test -f "$FACTORY_SKILLS_DIR/verify-behavior/SKILL.md"
check "factory agents present" "copy .pi/agents/factory/" test -f .pi/agents/factory/factory-reviewer.md
check "lead playbook present" "copy .pi/prompts/factory.md" test -f .pi/prompts/factory.md
check "issue tracker configured for skills" "run /setup-matt-pocock-skills (local markdown tracker, .scratch/)" test -f docs/agents/issue-tracker.md

section "Validation"
check "factory gate in CI" "add 'include: - local: .factory/ci/factory.gitlab-ci.yml' to $ci, then enable 'Pipelines must succeed'" \
  bash -c "grep -qE '^factory-gate:|factory\.gitlab-ci\.yml' '$ci' 2>/dev/null"
check "lint step in CI" "add a lint job before the factory stage" has_line 'lint' "$ci"
check "test step in CI" "add a test job before the factory stage" has_line '(npm|pnpm|yarn) (run )?test|pytest|go test|mvn .*test|gradle.* test' "$ci"
check "integration checks configured" "set FACTORY_LINT_CMD and FACTORY_TEST_CMD in .factory/commands.env" has_line '^FACTORY_TEST_CMD="[^"]+"' .factory/commands.env
check "pre-commit hooks" "add .pre-commit-config.yaml or husky, so agents get feedback before CI" \
  bash -c 'test -f .pre-commit-config.yaml || test -d .husky || test -f lefthook.yml'

section "Security"
check "security scan in CI" "include Jobs/SAST and Jobs/Secret-Detection templates" has_line 'SAST|Secret-Detection' "$ci"

section "Lanes and models"
check "behavior paths defined" "list behavior paths in .factory/behavior-paths" nonempty "$FACTORY_BEHAVIOR_PATHS_FILE"
check "models: one per role, judges on other families" "set model: in each .pi/agents/factory/*.md; see node scripts/factory/models-lint.mjs" \
  node "$here/models-lint.mjs"

section "Code health and safety"
check "quality bar written" "sharpen docs/agents/quality-bar.md for this repo (G5)" test -f docs/agents/quality-bar.md
check "health baseline committed" "scripts/factory/health.sh baseline, then commit .factory/health-baseline.json" test -f "$FACTORY_HEALTH_BASELINE"
check "repo health tool configured" "set FACTORY_HEALTH_CMD in .factory/commands.env (complexity/duplication thresholds, e.g. lizard, jscpd)" has_line '^FACTORY_HEALTH_CMD="[^"]+"' .factory/commands.env
check "command guard installed" "copy .pi/extensions/factory-guard.ts; trust the project in Pi" test -f .pi/extensions/factory-guard.ts

section "Behavior validation"
check "instrument has scenarios" "write scenarios under $FACTORY_INSTRUMENT_DIR/scenarios (validator only)" any_file "$FACTORY_INSTRUMENT_DIR/scenarios/*.yaml"
check "harness runnable" "build the harness (first mission), executable at ./harness" test -x ./harness
check "raw results ignored by git" "add $FACTORY_INSTRUMENT_DIR/results/ to .gitignore" bash -c "grep -q '$FACTORY_INSTRUMENT_DIR/results' .gitignore"

section "Dev environment"
check "env vars documented" "add .env.example listing every variable the bot reads" test -f .env.example
check "worktree port file ignored" "add .env.factory to .gitignore" bash -c "grep -q '.env.factory' .gitignore"
check "pi-subagents artifacts ignored" "add .pi-subagents/ to .gitignore" bash -c "grep -q '.pi-subagents/' .gitignore"

printf '\nReadiness: %s/%s\n' "$pass" "$total"
if [ "$strict" -eq 1 ] && [ "$pass" -lt "$total" ]; then exit 1; fi
exit 0
