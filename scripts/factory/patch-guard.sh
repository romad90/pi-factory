#!/usr/bin/env bash
# Deterministic safety check on a change, before it can be committed (D51).
# Runs on every worker patch in integrate.sh and on fix-lane diffs. Whatever
# an agent did in its worktree, nothing below lands in the repo.
#
# Usage: scripts/factory/patch-guard.sh <patch-file> [--human]
#   --human  fix lane (a person made the change): protected paths are allowed
#            (they may be the point of the fix), every other rule applies.
# Exit: 0 clean, 1 blocked (reasons on stdout, one per line).
#
# Blocks:
#   paths    instrument/, the factory itself (.factory/ scripts/factory/ .pi/),
#            CI and hooks (.gitlab-ci.yml .github/ .husky/ .pre-commit-config.yaml
#            lefthook.yml .git/)
#   tests    deleted test files
#   skips    added .skip( .only( xit( @pytest.mark.skip t.Skip( @Disabled @Ignore
#   silence  added eslint-disable, @ts-ignore, @ts-nocheck, # noqa, //nolint,
#            # type: ignore, # pragma: no cover, --no-verify
#   secrets  private keys, cloud and VCS tokens, hard-coded passwords/keys
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

patch="${1:?usage: patch-guard.sh <patch-file> [--human]}"
human=0; [ "${2:-}" = "--human" ] && human=1
[ -f "$patch" ] || die "no patch at $patch"

reasons=()
block() { reasons+=("$1"); }

# Files touched, both sides (a rename moves a file out of somewhere too),
# with quoted paths decoded: status, old, new, new mode (separator \x1f,
# never whitespace, so an empty side stays an empty field).
touched="$(node "$here/patch-paths.mjs" list "$patch")"

protected="^(${FACTORY_INSTRUMENT_DIR}/|\\.factory/|scripts/factory/|\\.pi/|\\.github/|\\.gitlab-ci\\.yml$|\\.husky/|\\.pre-commit-config\\.yaml$|lefthook\\.yml$|\\.git/)"
check_path() {                          # <path>
  local f="$1"
  [ -n "$f" ] || return 0
  if [[ "$f" =~ ^${FACTORY_INSTRUMENT_DIR}/ ]]; then
    block "paths: $f is in the instrument, hidden from workers (D21)"
  elif [ "$human" -eq 0 ] && [[ "$f" =~ $protected ]]; then
    block "paths: $f belongs to the factory, CI or hooks; agents never change them (a human does, through the fix lane)"
  fi
}
while IFS=$'\x1f' read -r st old new mode; do
  [ -n "${st:-}" ] || continue
  check_path "$old"; [ "$new" = "$old" ] || check_path "$new"
  if is_test_file "$old" && { [ "$st" = D ] || { [ "$st" = R ] && ! is_test_file "$new"; }; }; then
    block "tests: $old deleted; tests are never removed to make a change pass"
  fi
  [ "$mode" != 120000 ] || block "paths: ${new:-$old} is a symbolic link; a link can point at the instrument or outside the project"
done <<<"$touched"

# Added lines only (not the +++ header).
added="$(grep -E '^\+' "$patch" | grep -vE '^\+\+\+ ' || true)"
check_added() {                        # <rule> <ERE> <message>
  local hit
  hit="$(grep -nE -- "$2" <<<"$added" | awk 'NR == 1' || true)"
  [ -z "$hit" ] || block "$1: $3 (${hit:0:120})"
}
check_added skips   '\.(skip|only)\(|(^|[^A-Za-z_])x(it|describe|test)\(|@pytest\.mark\.skip|t\.Skip\(|@Disabled|@Ignore' \
  "a test was skipped or focused"
check_added silence 'eslint-disable|@ts-ignore|@ts-nocheck|#[[:space:]]*noqa|//[[:space:]]*nolint|#[[:space:]]*type:[[:space:]]*ignore|pragma:[[:space:]]*no cover|--no-verify' \
  "a check was silenced"
check_added secrets '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|(password|passwd|secret|api_?key|token)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'$<{ ]{8,}["'"'"']' \
  "something that looks like a secret was added"

if [ ${#reasons[@]} -eq 0 ]; then echo "patch-guard: clean"; exit 0; fi
printf 'BLOCKED %s\n' "${reasons[@]}"
exit 1
