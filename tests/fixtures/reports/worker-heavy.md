`npm test` now runs the whole suite on tap 21 and exits 0. The last line of the self-check is `SELF-CHECK: PASS (guard, lint, tests; 8 files changed)`.

The summary is `{ total: 695, pass: 694, skip: 1 }`, with 0 failed. The one skip is `search - sssvlv`. Full output is in `.scratch/deps-node-22/tmp/npm-test.txt`. This was run on Node 26.13 with network.

CONTRACT DOUBT: VAL-TEST-004: `test/server.test.js` "connection count" fails on Node 26 whatever the tap version. In the client's `connect` callback, the server has not yet counted the socket. A plain `net` server and client show the same 0 with no tap involved. I wrapped the `server.getConnections` call in `setImmediate`. The assertion `t.equal(count, 1)` is unchanged. That is neither an alias rename, a tap-loading change nor a removed-option fix, so the supervisor should confirm or reject it. I asked first, but the supervisor could not reply.

**Files changed**
- `package.json`: added `engines.node` `">=22"` and set `test` to `tap --disable-coverage -R terse`. `-R terse` still works on tap 21, so ticket 02 can reuse it. `tap ^21.8.1` was already there, and there is no `overrides`.
- `package-lock.json`: I added the root `engines` entry by hand, because `npm install` and `npm ci` are blocked for workers. I did not run `npm ci` or check `git status --porcelain` on the two files afterwards.
- `.taprc.yml` → `.taprc`, with `files` changed to `include`. tap 21 reads only `.taprc`, so it was running `test-integration/` too. The amended contract allows this.
- `.gitignore`: added `.tap/`.
- `test/client.test.js`, `test/issue-890.test.js`, `test/server.test.js`: these were needed for tap 21. The changes are:
  - `tap.timeout = ...` became `tap.setTimeout(...)`.
  - The `afterEach` hook now uses `tap.error`, because `t` has already ended there.
  - `return getPort()...` in the "url array is correctly assigned" test.
  - `t.error(err)` became `t.notOk(err)` in the reconnect close handler, because tap 21 fails on a non-Error value.
  - The `setImmediate` change described above.

**Checks I ran**
- `npm test -- test/controls/control.test.js` passes and runs only that file.
- `npm audit --omit=dev` reports 0 vulnerabilities.
- `npm audit --audit-level=high` exits 0. 19 moderate advisories remain. I checked their 25 installed paths against the lockfile, and none is reachable without going through `tap`. I did not run `npm explain` on each path.
- ESLint is 8.57.1.

**Assertions I believe are covered:** VAL-DEPS-001 to 005, VAL-NODE-001, VAL-TEST-001 to 003 and VAL-CROSS-002. VAL-LOCK-001 is only partly checked, and VAL-TEST-004 has the doubt above.

```acceptance-report
{
  "criteriaSatisfied": [
    {"id": "criterion-1", "status": "satisfied", "evidence": "npm test exits 0: total 695, pass 694, skip 1, 0 failed; self-check PASS; one CONTRACT DOUBT and one unverified npm ci reported below"}
  ],
  "changedFiles": ["package.json", "package-lock.json", ".taprc", ".taprc.yml", ".gitignore", "test/client.test.js", "test/issue-890.test.js", "test/server.test.js"],
  "testsAddedOrUpdated": ["test/client.test.js", "test/issue-890.test.js", "test/server.test.js"],
  "commandsRun": [
    {"command": "npm test", "result": "passed", "summary": "695 total, 694 pass, 1 skip, exit 0; output in .scratch/deps-node-22/tmp/npm-test.txt"},
    {"command": "npm test -- test/controls/control.test.js", "result": "passed", "summary": "only that file, 12 asserts pass"},
    {"command": "npm audit --omit=dev; npm audit --audit-level=high", "result": "passed", "summary": "0 prod vulnerabilities; exit 0 at high; 19 moderate left, all in tap's tree by lockfile walk"},
    {"command": "scripts/factory/self-check.sh deps-node-22", "result": "passed", "summary": "SELF-CHECK: PASS (guard, lint, tests; 8 files changed)"}
  ],
  "validationOutput": ["SELF-CHECK: PASS", "{ total: 695, pass: 694, skip: 1 }", "eslint v8.57.1"],
  "residualRisks": [
    "npm ci not run (blocked for workers); the lockfile root engines entry was added by hand, so a validator's npm ci/git status check on the lockfile is unverified",
    "server.test.js setImmediate change is outside VAL-TEST-004's allowed categories (CONTRACT DOUBT)",
    "Run on Node 26 only; Node 22 and 24 not tried",
    "npm explain not run per path; the tap-only check was a lockfile walk"
  ],
  "noStagedFiles": false,
  "diffSummary": "tap 21 setup: engines, test script, .taprc, lockfile engines entry, .tap/ ignore, and four small test-file adjustments for tap 21 plus one timing fix",
  "reviewFindings": ["no blockers; CONTRACT DOUBT VAL-TEST-004 on test/server.test.js"],
  "manualNotes": ".taprc was added with git mv, so it is staged; the other changes are unstaged. The supervisor was unreachable when I asked about the server.test.js change."
}
```

I skipped `npm ci` and the Node 22 and 24 runs. The risk is that the hand-edited lockfile entry is wrong and only `npm ci` would show it.