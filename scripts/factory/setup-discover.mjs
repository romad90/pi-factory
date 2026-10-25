#!/usr/bin/env node
// Setup, step 1: discover (D102, proposal P18). Reads the project's own
// sources of truth (its manifests, its CI file, its install scripts) and
// prints what the factory should run, with where each candidate came from, and
// what needs a person's decision. Installs nothing, runs nothing.
//
// Usage: node scripts/factory/setup-discover.mjs [project-dir]   → JSON on stdout
//   { ecosystems: [], candidates: { test, testFiles, lint, extra }: [{ cmd, source }],
//     probe: { file, content } | null, ci: [{ kind, cmd, source }],
//     findings: [{ level: "decide"|"warn"|"info", topic, text }] }
// Ecosystems: Node (npm, yarn, pnpm), Python, Go, Rust, JVM (Maven, Gradle), and
// a Makefile's test and lint targets.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, dirname, extname } from "node:path";

const dir = process.argv[2] || process.cwd();
const at = (p) => join(dir, p);
const exists = (p) => existsSync(at(p));
const read = (p) => { try { return readFileSync(at(p), "utf8"); } catch { return ""; } };
const json = (p) => { try { return JSON.parse(read(p)); } catch { return null; } };
const git = (...a) => { try { return execFileSync("git", ["-C", dir, ...a], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch { return ""; } };
const gitRoot = git("rev-parse", "--show-toplevel").trim() || dir;
const tracked = git("ls-files").split("\n").filter(Boolean);

const out = { ecosystems: [], candidates: { test: [], testFiles: [], lint: [], extra: [] }, probe: null, ci: [], findings: [] };
const cand = (kind, cmd, source) => { if (!out.candidates[kind].some((c) => c.cmd === cmd)) out.candidates[kind].push({ cmd, source }); };
const finding = (level, topic, text) => out.findings.push({ level, topic, text });
const glob = (re) => readdirSync(dir).filter((f) => re.test(f));

// Test files the repository tracks (the factory's own pattern, D50).
const TEST_RE = /(^|\/)(tests?|__tests__|spec|specs)\/|[._-](test|spec)\.[a-z]+$|_test\.(go|py)$|(^|\/)test_[^/]+\.py$/;
const testFiles = tracked.filter((f) => TEST_RE.test(f) && !/(^|\/)(node_modules|vendor|dist|build)\//.test(f) && !/\.gitkeep$/.test(f));

// ---------------------------------------------------------------- Node
const pkg = json("package.json");
if (pkg) {
  out.ecosystems.push("node");
  const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}), ...(pkg.optionalDependencies || {}) };
  const scripts = pkg.scripts || {};
  const pm = exists("pnpm-lock.yaml") ? "pnpm" : exists("yarn.lock") ? "yarn" : exists("bun.lockb") || exists("bun.lock") ? "bun" : "npm";
  const installCmd = { npm: "npm ci", pnpm: "pnpm install --frozen-lockfile", yarn: "yarn install --frozen-lockfile", bun: "bun install --frozen-lockfile" }[pm];
  const addDev = { npm: "npm install -D --ignore-scripts", pnpm: "pnpm add -D --ignore-scripts", yarn: "yarn add -D --ignore-scripts", bun: "bun add -d" }[pm];
  // Binaries: the project's node_modules, else the repository root's (hoisted, monorepo).
  const binPath = (b) => {
    if (existsSync(at(`node_modules/.bin/${b}`))) return `node_modules/.bin/${b}`;
    const r = join(gitRoot, "node_modules/.bin", b);
    return existsSync(r) ? relative(dir, r) : "";
  };
  const installed = existsSync(at("node_modules")) || existsSync(join(gitRoot, "node_modules"));
  if (!installed) finding("decide", "dependencies", `dependencies are not installed here: install them first (\`${installCmd}\`), since workers link this checkout's node_modules (D65) and setup rehearses with them`);

  // Install scripts run on every install, CI included.
  const life = ["preinstall", "install", "postinstall", "prepare"].filter((k) => scripts[k]);
  const WRITES = /audit\s+fix|\bnpm\s+(i|install|update|ci)\b|\b(yarn|pnpm)\s+(add|install|upgrade|update)\b|\bgit\s|husky|patch-package|sed\s+-i|(^|\s)>{1,2}\s*\S|\brm\s/;
  for (const k of life) {
    const writes = WRITES.test(scripts[k]);
    finding(writes ? "decide" : "info", "install scripts", writes
      ? `\`${k}: ${scripts[k]}\` runs on every install and can change the dependencies or files behind your back (CI included): install with \`${installCmd} --ignore-scripts\` on this machine, and raise it with the team`
      : `\`${k}: ${scripts[k]}\` runs on every install`);
  }

  // Test runners: configured, declared, installed.
  const runners = [
    ["jest", deps.jest || pkg.jest || glob(/^jest\.config\.(js|cjs|mjs|ts|json)$/).length],
    ["vitest", deps.vitest || glob(/^vitest\.config\.(js|cjs|mjs|ts|mts)$/).length || glob(/^vite\.config\./).length && /\btest\s*:/.test(read(glob(/^vite\.config\./)[0] || ""))],
    ["mocha", deps.mocha || glob(/^\.mocharc/).length],
    ["ava", deps.ava],
  ].filter(([, on]) => on).map(([r]) => r);
  const ts = exists("tsconfig.json");
  for (const r of runners) {
    const bin = binPath(r);
    if (!deps[r] && !bin) {
      const extra = r === "jest" && ts ? " ts-jest @types/jest" : r === "mocha" && ts ? " ts-node @types/mocha" : "";
      finding("decide", "test runner", `${r} is configured but is not a dependency: \`npx ${r}\` would download it, a different version each time, and a worker, offline, can't. Add it as test tooling: \`${addDev} ${r}${extra}\` (package.json and the lock change, nothing else)`);
    } else if (deps[r] && !bin && installed) {
      finding("decide", "test runner", `${r} is declared but not installed: install the dependencies (\`${installCmd}\`)`);
    }
  }
  if (runners.includes("jest") && ts) {
    const jcfg = glob(/^jest\.config\./).map(read).join("\n") + JSON.stringify(pkg.jest || {});
    if (!deps["ts-jest"] && !deps["@swc/jest"] && !/ts-jest|@swc\/jest|babel-jest/.test(jcfg) && !deps["@babel/preset-typescript"])
      finding("decide", "test runner", "TypeScript with jest, but no ts-jest (or @swc/jest, or babel's TypeScript preset): .ts tests can't run. Add ts-jest and a transform for .ts files");
    const mfe = jcfg.match(/moduleFileExtensions\s*:\s*\[([^\]]*)\]/);
    if (mfe && !/['"]ts['"]/.test(mfe[1]))
      finding("decide", "test runner", `jest's moduleFileExtensions is [${mfe[1].trim()}]: .ts files are never loaded, so .ts tests never run. Add 'ts' (and a ts-jest transform)`);
    if (/collectCoverageFrom[^\]]*dist\//.test(jcfg))
      finding("info", "test runner", "jest's coverage is collected from dist/: the tests were written against the build output; the factory's tests run against the sources");
  }
  if (!testFiles.length) finding("info", "tests", "the repository tracks no test files: the base is green with an empty suite, and the mission's first tests are the only ones");

  // Candidates, the most precise first: the local runner binary.
  // The project's own test script, when it is one runner call with its
  // options (a config file, a project): the same run, through the local binary.
  const own = (scripts.test || "").match(/^\s*(jest|vitest|mocha)\b((?:\s+[-\w=.,/:@'"]+)*)\s*$/);
  if (own && binPath(own[1])) {
    const opts = own[2].replace(/\s+--?(watch|watchAll)\b/g, "").trim();
    const pass = /jest|vitest/.test(own[1]) && !/passWithNoTests/.test(opts) ? " --passWithNoTests" : "";
    const sub = own[1] === "vitest" && !/^\s*run\b/.test(opts) ? " run" : "";
    if (opts) {
      cand("test", `${binPath(own[1])}${sub}${opts ? " " + opts : ""}${pass}`, `package.json scripts.test (${scripts.test}), through the local binary`);
      cand("testFiles", `${binPath(own[1])}${sub}${opts ? " " + opts : ""}${pass} {files}`, "package.json scripts.test, through the local binary");
    }
  } else if (scripts.test && !/no test specified/.test(scripts.test) && !/^\s*(jest|vitest|mocha)\s*$/.test(scripts.test)) {
    cand("test", `${pm} test`, `package.json scripts.test (${scripts.test}): more than one runner call, run as the team runs it`);
  }
  const jest = binPath("jest"), vitest = binPath("vitest"), mocha = binPath("mocha");
  if (jest) { cand("test", `${jest} --passWithNoTests`, "jest, installed"); cand("testFiles", `${jest} --passWithNoTests {files}`, "jest, installed"); }
  if (vitest) { cand("test", `${vitest} run --passWithNoTests`, "vitest, installed"); cand("testFiles", `${vitest} run --passWithNoTests {files}`, "vitest, installed"); }
  if (mocha) { cand("test", mocha, "mocha, installed"); cand("testFiles", `${mocha} {files}`, "mocha, installed"); }
  if (/\bnode\s+--test\b/.test(scripts.test || "")) { cand("test", "node --test", "package.json scripts.test"); cand("testFiles", "node --test {files}", "package.json scripts.test"); }
  if (scripts.test && !/no test specified/.test(scripts.test)) cand("test", `${pm} test`, `package.json scripts.test (${scripts.test})`);

  // Lint: eslint when configured, the type checker for TypeScript.
  const eslint = binPath("eslint"), tsc = binPath("tsc");
  const eslintCfg = glob(/^(eslint\.config\.(js|cjs|mjs|ts)|\.eslintrc(\.(js|cjs|json|yml|yaml))?)$/).length || pkg.eslintConfig;
  if (eslint && eslintCfg) cand("lint", `${eslint} .`, "eslint, configured and installed");
  if (tsc && ts) cand(eslint && eslintCfg ? "extra" : "lint", `${tsc} --noEmit --pretty false`, "TypeScript's type checker, installed");
  if (eslintCfg && !eslint) finding("warn", "lint", "eslint is configured but not installed");
  if (exists("tslint.json") && !binPath("tslint"))
    finding("info", "lint", "tslint.json is here but tslint isn't installed (it has been deprecated since 2019)" + (tsc && ts ? "; the type checker is the lint candidate" : ""));

  // Build-time environment inlining.
  const babel = read(".babelrc") + read("babel.config.js") + read("babel.config.json") + JSON.stringify(pkg.babel || {});
  if (/transform-inline-environment-variables/.test(babel) || deps["babel-plugin-transform-inline-environment-variables"])
    finding("warn", "build", "babel's transform-inline-environment-variables writes the values of environment variables into the build output: a secret present when CI builds ends up in plain text in the artifact, and the code's behavior depends on the build environment (characterization tests must set the variables they rely on)");
  if (/DefinePlugin[\s\S]{0,200}process\.env/.test(glob(/^webpack\.config\./).map(read).join("\n")))
    finding("warn", "build", "webpack's DefinePlugin inlines process.env values at build time: check which variables reach the bundle");

  // The probe: a test file that must fail, where this project keeps its tests.
  const ext = (() => {
    const counts = {};
    for (const f of testFiles) { const e = extname(f); if (/^\.(c|m)?[jt]sx?$/.test(e)) counts[e] = (counts[e] || 0) + 1; }
    const best = Object.entries(counts).sort((a, b) => b[1] - a[1])[0];
    return best ? best[0] : ts ? ".ts" : ".js";
  })();
  const testDir = testFiles.length ? dirname(testFiles.find((f) => extname(f) === ext) || testFiles[0])
    : ["tests", "test", "__tests__", "src"].find((d) => tracked.some((f) => f.startsWith(d + "/"))) || ".";
  if (runners.length || out.candidates.test.length)
    out.probe = { file: join(testDir, `factory-setup-probe.test${ext}`).replace(/^\.\//, ""), content: 'throw new Error("factory setup probe: this file must fail");\n' };
}

// ---------------------------------------------------------------- Python
const pyproject = read("pyproject.toml");
if (pyproject || exists("setup.py") || exists("setup.cfg") || glob(/^requirements.*\.txt$/).length || exists("pytest.ini") || exists("tox.ini")) {
  out.ecosystems.push("python");
  const reqs = pyproject + glob(/^requirements.*\.txt$/).map(read).join("\n") + read("setup.cfg") + read("tox.ini");
  const venv = [".venv", "venv"].find((v) => existsSync(at(`${v}/bin/python`)));
  const py = venv ? `${venv}/bin/python` : "python3";
  if (!venv) finding("info", "dependencies", "no .venv here: tests run with the system python3; workers link .venv when there is one (D65)");
  const pytest = /\bpytest\b/.test(reqs) || exists("pytest.ini") || /\[tool\.pytest/.test(pyproject) || testFiles.some((f) => f.endsWith(".py"));
  if (pytest) {
    cand("test", `${py} -m pytest -q`, "pytest");
    cand("testFiles", `${py} -m pytest -q {files}`, "pytest");
    const td = ["tests", "test"].find((d) => tracked.some((f) => f.startsWith(d + "/"))) || ".";
    out.probe ??= { file: join(td, "test_factory_setup_probe.py").replace(/^\.\//, ""), content: 'def test_factory_setup_probe():\n    assert False, "factory setup probe: this test must fail"\n' };
  }
  if (/\bruff\b/.test(reqs)) cand("lint", `${venv ? venv + "/bin/" : ""}ruff check --output-format concise .`, "ruff");
  else if (/\bflake8\b/.test(reqs)) cand("lint", `${py} -m flake8 .`, "flake8");
}

// ---------------------------------------------------------------- Go, Rust, JVM
if (exists("go.mod")) {
  out.ecosystems.push("go");
  cand("test", "go test ./...", "go.mod");
  cand("lint", "go vet ./...", "go.mod");
  finding("info", "tests", "Go tests run per package, not per file: FACTORY_TEST_FILES_CMD stays empty, and test on base runs the whole suite");
}
if (exists("Cargo.toml")) {
  out.ecosystems.push("rust");
  cand("test", "cargo test --offline", "Cargo.toml");
  cand("extra", "cargo check --offline --message-format short", "Cargo.toml");
}
if (exists("pom.xml")) { out.ecosystems.push("maven"); cand("test", `${exists("mvnw") ? "./mvnw" : "mvn"} -o -q test`, "pom.xml"); }
if (exists("build.gradle") || exists("build.gradle.kts")) { out.ecosystems.push("gradle"); cand("test", `${exists("gradlew") ? "./gradlew" : "gradle"} --offline test`, "build.gradle"); }

// ---------------------------------------------------------------- Makefile
const make = read("Makefile");
if (/^test\s*:/m.test(make)) cand("test", "make test", "Makefile");
if (/^lint\s*:/m.test(make)) cand("lint", "make lint", "Makefile");

// ---------------------------------------------------------------- CI file
// What the team's pipeline runs, and which jobs a branch push starts.
const gitlab = read(".gitlab-ci.yml");
if (gitlab) {
  const lines = gitlab.split("\n");
  let job = "", stage = "", inScript = false, hasTests = false;
  const jobs = [];
  lines.forEach((line, i) => {
    const top = line.match(/^([A-Za-z0-9_.\-\/][A-Za-z0-9_.\-\/ ]*):\s*$/);
    if (top) { job = top[1]; stage = ""; inScript = false; jobs.push({ name: job, line: i + 1, rules: [], stage: "" }); return; }
    const st = line.match(/^\s+stage:\s*(\S+)/); if (st && jobs.length) { stage = st[1]; jobs[jobs.length - 1].stage = stage; }
    if (/^\s+(script|before_script):\s*$/.test(line)) { inScript = true; return; }
    if (/^\s+[a-z_]+:/.test(line) && !/^\s+-/.test(line)) inScript = false;
    const rule = line.match(/^\s+-\s+if:\s*(.*)$/); if (rule && jobs.length) jobs[jobs.length - 1].rules.push({ text: rule[1], line: i + 1 });
    const cmd = inScript && line.match(/^\s+-\s+(.*)$/);
    if (!cmd) return;
    const c = cmd[1].replace(/^['"]|['"]$/g, "");
    const src = `.gitlab-ci.yml:${i + 1} (job ${job})`;
    if (/\b(jest|vitest|mocha|pytest|go test|cargo test|mvn\b.*\btest|gradle\w*\b.*\btest|(npm|yarn|pnpm)( run)? test)/.test(c)) { out.ci.push({ kind: "test", cmd: c, source: src }); hasTests = true; }
    else if (/\b(eslint|tslint|tsc\b|ruff|flake8|pylint|golangci|clippy|go vet|(npm|yarn|pnpm)( run)? lint)/.test(c)) out.ci.push({ kind: "lint", cmd: c, source: src });
  });
  if (!hasTests) finding("info", "ci", "the CI file runs no tests: the factory's gates are the only test runs on this code");
  // A push of the mission branch starts these jobs (mr.sh pushes before opening the MR).
  for (const j of jobs) {
    for (const r of j.rules) {
      const anyBranch = /\$CI_COMMIT_BRANCH\s*!=/.test(r.text) || /CI_PIPELINE_SOURCE\s*==\s*["']push["']/.test(r.text);
      if (anyBranch) {
        const deploy = /deploy|release|publish|prod|staging|dev/i.test(j.name + " " + j.stage);
        finding(deploy ? "decide" : "warn", "ci", `job \`${j.name}\`${j.stage ? ` (stage ${j.stage})` : ""} runs when a branch other than the ones it names is pushed (.gitlab-ci.yml:${r.line}): mr.sh pushes the mission branch before opening the MR${deploy ? ", so this job would run; if it deploys, add the mission branch pattern to FACTORY_MR_BLOCKED_BRANCHES or have the job skip it" : "; check what it does"}`);
        break;
      }
    }
  }
}
for (const f of (existsSync(at(".github/workflows")) ? readdirSync(at(".github/workflows")) : []).filter((f) => /\.ya?ml$/.test(f))) {
  read(`.github/workflows/${f}`).split("\n").forEach((line, i) => {
    const m = line.match(/^\s+(?:-\s+)?run:\s*(.+)$/); if (!m) return;
    const c = m[1].replace(/^['"|>]|['"]$/g, "").trim(); const src = `.github/workflows/${f}:${i + 1}`;
    if (/\b(jest|vitest|mocha|pytest|go test|cargo test|(npm|yarn|pnpm)( run)? test)/.test(c)) out.ci.push({ kind: "test", cmd: c, source: src });
    else if (/\b(eslint|tsc\b|ruff|flake8|golangci|clippy|(npm|yarn|pnpm)( run)? lint)/.test(c)) out.ci.push({ kind: "lint", cmd: c, source: src });
  });
}

// ---------------------------------------------------------------- secrets in the tree
const envFiles = tracked.filter((f) => /(^|\/)\.env(\.[A-Za-z0-9_-]+)?$/.test(f) && !/\.(example|sample|template|factory)$/.test(f));
if (envFiles.length)
  finding("warn", "secrets", `tracked environment files: ${envFiles.join(", ")}. If they hold real values, those are in git history (rotate them, don't just delete the files); every worker worktree checks them out. The guard refuses agents reading them; tests must set their own variables and never load these files`);

if (!out.ecosystems.length) finding("decide", "ecosystem", "no manifest the factory knows (package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, build.gradle): set FACTORY_TEST_CMD by hand");
if (!out.candidates.test.length) finding("decide", "tests", "no test command found: set FACTORY_TEST_CMD by hand (the factory refuses to build without one, D44)");

console.log(JSON.stringify(out, null, 2));
