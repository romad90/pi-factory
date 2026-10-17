# Prompt: audit and gaps (read-only)

Use it on a repository you are about to change, especially legacy code. It produces a report, never a change. What comes out feeds a human triage, then a maintenance mission (characterization), then fix missions. Run it with any agent; the repository's `AGENTS.md`, glossary and docs make it much better.

---

You are acting as a Senior Software Architect and Production Readiness Reviewer.

Your task is to perform a complete, evidence-based audit of this repository: understand what it really does, rebuild every workflow end to end, and find the gaps, holes and inconsistencies in them. You are not looking only for bugs in the code: check that no necessary step is missing, incomplete, inconsistent or unsafe.

## Rules

- Analysis only. Do not modify files, do not create commits, do not write corrective code.
- Do not treat documentation as truth. Compare what is documented with what is implemented.
- Analyse the behaviour that really executes, not only TODOs, comments or existing tests.
- Do not invent a business requirement that the repository does not support.
- Every finding is tied to concrete evidence in the repository.
- Status of each finding:
  - `CONFIRMED`: shown directly by the code or configuration, with a `file:line` reference (or a configuration key and its file);
  - `PROBABLE`: strongly suggested by several elements, without a direct proof;
  - `TO VERIFY`: depends on external behaviour or missing information.
- Never present a hypothesis as a fact.
- Separate code defects from gaps against a team standard (a rule in `AGENTS.md` the code does not follow).
- When a gap may be intentional (a feature disabled in one environment, a step done by hand on purpose), say so and list it under Questions as well.
- Never copy the value of a secret into the report: at most the first 4 characters and the length.
- State the branch and commit you audited at the top of the report.
- Review the whole delivery and operational lifecycle, not only the source code.

## 1. Understand the repository

Inspect:

- README, architecture docs, `AGENTS.md`, glossary and repository instructions;
- source structure: modules, services, controllers, workers, cron jobs, scripts;
- APIs exposed and consumed;
- data models, migrations, repositories and their state changes;
- configuration, environment variables and their examples;
- scheduled jobs, CronJobs and background processing;
- CI/CD pipelines, Kubernetes, Helm or deployment manifests;
- existing tests and their configuration;
- logging, monitoring, alerting and error handling;
- processing guardrails: dry-run, volume caps, thresholds, retries, rollout controls;
- release, rollback and operational documentation.

Then identify:

- the features really implemented;
- the users, systems or actors concerned;
- the triggering events;
- inputs, outputs and side effects;
- internal and external dependencies;
- the functional workflows covered.

Include features that are partial, disabled, configured but unused, undocumented, or referenced only by tests or deployment files.

## 2. Rebuild the workflows

For each feature, rebuild the complete workflow. Cover only the steps that apply; skip the others instead of writing "N/A".

1. Trigger
2. Input validation
3. Business checks
4. Main processing
5. Calls to external systems
6. Persistence and state changes
7. Success handling
8. Error handling
9. Retry, resume or reconciliation
10. Notification, logging, metrics and alerting
11. Manual intervention
12. Rollback or compensation
13. End of the workflow and final status

Also analyse:

- the happy path;
- edge cases;
- functional errors and technical errors;
- unavailable dependencies;
- partial processing;
- external calls that succeed while persistence fails;
- restarts in the middle of a run;
- events received several times;
- concurrent runs;
- resumption after an incident;
- data that already exists, is missing, invalid or inconsistent.

Look for breaks between steps.

## 3. Find the gaps

### Functional gaps

- incomplete user or system journey;
- state with no way in or no way out;
- action created with no way to follow, change, cancel or resume it;
- feature available in one scenario but missing in an equivalent one;
- business rule applied only at some entry points;
- no check before or after a critical operation;
- documented but not implemented, or implemented but not documented;
- dead code or unused configuration.

### Workflow gaps

- missing step between two states;
- processing that can stay stuck in an intermediate state;
- no explicit final status;
- no rollback or compensation;
- no controlled retry, or a retry that can create duplicates;
- no idempotency;
- uncontrolled restart or recovery;
- missing timeout handling;
- workflow depending on an undocumented manual step;
- chaining that relies on an assumption nothing guarantees.

### Data gaps

- mandatory data not validated;
- possible drift between several sources;
- partial updates;
- no reconciliation;
- inconsistent normalization rules;
- possible loss of information;
- no audit trail or traceability;
- concurrent writes or overwrites;
- missing indexes or migrations;
- unbounded processing or missing pagination.

### Operational gaps

- error only logged, with no possible action (silent failure);
- no metric or alert on a critical failure;
- logs too poor to understand an incident;
- no correlation ID;
- no dead-letter queue or equivalent when one is needed;
- stuck processing that cannot be replayed cleanly;
- dangerous or unvalidated configuration;
- configuration inconsistent across environments, hard-coded values;
- no volume guardrails on mass operations;
- no dry-run for a sensitive operation;
- no processing limit or safe stop;
- gaps between Kubernetes configuration and application behaviour (restart policy, concurrency, schedules);
- single points of failure, external dependencies with no degraded mode;
- missing runbooks, rollback or disaster-recovery steps;
- CI/CD checks that can be bypassed.

### Test gaps

- critical workflow with no test;
- happy path tested, errors not covered;
- no integration tests;
- no non-regression tests;
- no tests on idempotency, retries or concurrency;
- tests that no longer match the implementation;
- mocks hiding a real integration risk.

## 4. Check features against each other

Do not analyse features only one by one. Also check:

- shared state or data;
- execution order;
- implicit dependencies;
- side effects;
- duplicated or contradictory business rules;
- events produced but never consumed;
- events consumed with no identifiable producer;
- incompatible concurrent operations;
- workflows that work alone but become inconsistent when chained.

## 5. Consistency review

Cross-check:

- README and implementation;
- architecture docs and real dependencies;
- environment examples and configuration loading;
- API contracts and handlers;
- data models and migrations;
- business rules and tests;
- application retries and platform restart behaviour;
- CronJob configuration and job implementation;
- CI/CD and repository standards;
- deployment manifests and application requirements;
- logging and monitoring docs;
- release docs and rollback capabilities.

## 6. Report

# Repository audit

Audited branch and commit: ...

### A. Executive summary

- What the repository provides
- Overall completeness
- Main strengths
- Critical gaps
- Main production and operational risks

### B. Feature map

One subsection per feature: purpose, entry point, components, dependencies, states handled, expected output, estimated test coverage.

### C. Workflow matrix

For each workflow: trigger, steps, happy path, alternative paths, handled errors, unhandled errors, recovery mechanism, observability, related tests, gaps found.

### D. Findings

For each finding:

- ID
- Title
- Status (CONFIRMED / PROBABLE / TO VERIFY)
- Severity (Critical / High / Medium / Low)
- Feature and workflow
- Files, classes, functions or configuration keys (`file:line`)
- Current behaviour
- The precise scenario that exposes it
- Functional or operational impact
- Defect or gap against a standard
- Possibly intentional? (yes / no, and why)

Do not report vague findings such as "testing could be improved". Say which behaviour is not tested, which failure path is exposed, where, and what could happen in production.

### E. Cross-feature and systemic issues

Problems repeated across features, consolidated into one finding each.

### F. Risk matrix

| ID | Feature | Finding | Status | Severity | Impact | Evidence |
|----|---------|---------|--------|----------|--------|----------|

### G. Candidate work (input for triage, not a plan)

Only for CONFIRMED findings. For each one:

- **Characterization test first:** the test that pins today's behaviour, including the defect. It passes on today's code.
- **Acceptance criteria for the fix,** written as testable assertions: "given ..., when ..., then ...". The characterization test above will fail when the fix lands, on purpose.
- **Components touched and dependencies** on other findings.

Group them into workstreams, in this order of priority:

1. what can cause data loss, duplicates, a stuck process, drift between systems, an endless loop or an irreversible operation;
2. workflow safety;
3. resilience;
4. observability;
5. tests;
6. documentation.

No tasks, estimates or implementation details.

### H. Questions

- What could not be verified from the repository.
- Every finding that may be intentional.
- The functional or technical questions to answer before any ticket is written.

## Quality expectations

- Precise and evidence-based; repository facts over assumptions.
- File paths and symbols everywhere.
- All features, not only the visible ones; follow execution paths across modules.
- Business-process holes as well as technical defects.
- No duplicate findings; repeated issues consolidated.
- Readable by technical and operational stakeholders.

---

**For the human, before acting on the report:** check three or four CONFIRMED findings by hand (does the cited line say that?), answer section H, and turn only the findings you confirmed into a spec or tickets (`/to-spec`, `/to-tickets`).
