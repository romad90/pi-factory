# Contract critique: eslint-10

**Critique result:** FINDINGS

## Traceability: spec → contract

| Spec requirement | Assertions | Status |
|---|---|---|
| Replace ESLint 8 and the five obsolete direct dependencies with ESLint 10 and neostandard | VAL-DEPS-001, VAL-CONF-003 | covered |
| Preserve other package fields, dependency ranges, scripts, and `engines.node` | VAL-DEPS-002 | covered |
| Keep dependency changes in one isolated commit | VAL-CROSS-001 | covered for commit structure; human ownership and installation history require process evidence |
| Keep production advisories at zero and development high/critical advisories at zero | VAL-DEPS-003, VAL-CROSS-002 | covered |
| Retain error severity for `no-shadow` outside the two test folders | VAL-CONF-001, VAL-CONF-003 | partial; only two non-test paths have an effective severity assertion |
| Retain `no-unused-vars`, with only the specified underscore exceptions | VAL-CONF-001, VAL-CONF-003 | partial; additional ignore patterns can suppress unused variables |
| Keep CommonJS source and the standard style | VAL-CONF-001, VAL-CONF-002, VAL-CONF-003 | covered by configuration review and representative probes; target-package checks remain unverified |
| Preserve ignored folders and lint the measured 58 files | VAL-LINT-002, VAL-LINT-003, VAL-CONF-003 | covered |
| Remove all four legacy configuration files | VAL-CONF-003, VAL-CROSS-001 | covered |
| Apply only the two optional catch bindings and the comma relocation | VAL-SRC-001 | covered |
| Preserve caller-visible errors | VAL-SRC-001, VAL-SRC-002 | covered by exact source changes and two baseline comparisons |
| Add no disabled rule, suppression comment, or baseline entry | VAL-CONF-003, VAL-SRC-001, VAL-LINT-001, VAL-CROSS-001 | partial; enabled rules can still lose coverage through severity or option changes |
| Pass lint, the existing unit suite, audits, and the done-when command | VAL-LINT-001, VAL-TEST-001, VAL-CROSS-002 | covered |
| Restrict changed files and freeze `.github/` | VAL-CROSS-001 | covered |
| Leave network-dependent failures, moderate advisory counts, older development Node versions, and remote CI outside this mission | Not covered section | exclusions have reasons |

## Checklist

| Item | Assertions | Status |
|---|---|---|
| Present domain checklist packs | Not covered section | not applicable; `docs/agents/` contains no `contract-checklist-*.md` files |
| Stable assertion IDs and Given/When/Then/Evidence/Kind fields | All assertions | covered |
| Separate behavior checks from code review | Behavior and code assertions | covered |
| Observable commands, outputs, exit codes, and diffs | All assertions | covered; target-tool compatibility still needs confirmation |
| Negative checks for ignored paths and invalid inputs | VAL-LINT-003, VAL-SRC-002 | covered |
| Checks against weakening lint policy | VAL-CONF-001, VAL-CONF-002, VAL-CONF-003 | partial; findings 1 and 2 describe passing regressions |
| Reasons for requirements outside validation | Not covered section | present |

## Findings

### 1. [blocking] Unsampled source files can lose `no-shadow` error severity

`VAL-CONF-001` checks only four files.
Only two paths represent source outside the test folders.
`VAL-CONF-003` references those checks and prohibits turning rules off, but does not prohibit warning severity elsewhere.

Passes wrongly: Add a final flat-config override setting `no-shadow` to `"warn"` for `lib/url.js` only.

The four printed configurations stay unchanged.
The rule remains enabled, and the baseline has no shadow finding in that file.
The file list, style probes, source diff, tests, audits, and allowed-path checks remain unchanged.
A future shadow violation in `lib/url.js` becomes a warning instead of the required error.

Suggested fix: Check effective `no-shadow` severity for every linted file outside `test/` and `test-integration/`.
Check that both test folders retain the exception.
Require configuration review to reject lower severity outside that exception.

### 2. [blocking] An extra ignore pattern can suppress all unused variables

`VAL-CONF-001` checks severity and two option values, but does not restrict other `no-unused-vars` options.
`VAL-CONF-003` does not close this gap because the rule can remain enabled at error severity.

Passes wrongly: Add `varsIgnorePattern: ".*"` to the configured `no-unused-vars` options while retaining both required `"^_"` patterns and error severity.

The printed configurations retain every asserted value.
The `var x = 1;` probe still fails for its semicolon, which `VAL-CONF-002` independently requires the configuration to reject.
Neither probe requires an error from `no-unused-vars`.
The existing clean files, exact source changes, tests, audits, and file-scope checks still pass.
Unused local variables would no longer produce the required errors.

Suggested fix: Restrict the override to the two specified ignore patterns.
Reject added options that reduce unused-variable checks.
Add a semicolon-free unused-local probe that must report `no-unused-vars` at error severity.

### 3. [non-blocking] Target-tool commands and rule identifiers remain unchecked

The contract states that the author checked ESLint command options only with ESLint 8.57.1.
It also marks neostandard options and stylistic rule identifiers as unchecked.
This does not identify a wrong change that passes every assertion.
It leaves the feasibility of the proposed evidence unconfirmed on the required tool versions.

Suggested fix: Confirm the marked commands and identifiers after the person records the dependency commit.
Record the actual ESLint 10 and neostandard outputs before validation relies on those checks.

## Review limits

I reviewed the specified documents and confirmed that no domain checklist packs are present.
I did not install dependencies, execute validation commands, inspect implementation files, or modify the contract.
The two blocking findings concern assertion coverage, not observed implementation changes.
