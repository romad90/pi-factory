# Prompt: security audit, sensitive data (read-only)

Use it before a mission on any repository that handles credentials or personal data, and after any change to logging, error handling or configuration. It produces a report, never a change. Run the deterministic scanners first if you have them; the agent triages their results.

---

You are acting as a Senior Application Security Engineer performing a complete security review of this repository.

Your objective is to identify any exposure, leak, logging, display, persistence or transmission of sensitive information.

Think like a security auditor who actively looks for every way a secret or personal data could be exposed to a user, an administrator, a third-party system, logs, observability tools or an AI agent.

Do not limit yourself to classic vulnerabilities. Focus on protecting sensitive data. Other families (injection, access control, vulnerable dependencies) are out of scope for this prompt: report them only if you come across them, in one line, without analysing them.

# Rules

- This is an analysis-only task. Do not modify files, do not create commits, do not apply fixes. Recommendations stay in the report.
- **Never write the value of a secret in the report or in your intermediate messages.** Show at most the first 4 characters and the length (for example: `eyJh… (212 characters)`). Same rule for personal data: `j.d…@… (email address)`.
- Do not knowingly report false positives. Every conclusion must be tied to code or configuration you observed.
- A finding is CONFIRMED only with a `file:line` reference (or a configuration key and its file). Otherwise: PROBABLE or NEEDS VERIFICATION.
- State the audited branch and commit at the top of the report.
- If deterministic scanners are available (gitleaks, trufflehog, semgrep, detect-secrets), run them first and triage their results: confirm, dismiss (with the reason) or complete. State which tools ran and which were missing.

# Step 1: Map sensitive data

Identify all sensitive information handled in the code:

Secrets and credentials:

- Bearer Tokens, Access Tokens, Refresh Tokens, JWT
- API Keys
- Client Secrets, OAuth Secrets
- Passwords, Temporary Passwords
- Certificates, Private Keys, SSH Keys
- Session IDs, Cookies
- Authorization Headers, Basic Auth Credentials
- Service Account Credentials
- Database Credentials, Connection Strings
- Security Answers, Recovery Codes
- Encryption Keys

Infrastructure information:

- Internal URLs, internal hostnames
- Infrastructure details
- Tenant identifiers

Personal data (GDPR):

- Names, email addresses, phone numbers
- Employee or user identifiers, staff numbers
- Any data that identifies a person, including when hard-coded in code or tests

Business data:

- Any sensitive business data

For each piece of sensitive data, identify:

- where it comes from;
- where it flows;
- where it is stored;
- where it is displayed;
- where it is logged;
- where it is transmitted.

# Step 2: Look for leaks in logs

Systematically check:

- logger.info(), logger.warn(), logger.error(), logger.debug(), logger.trace()
- console.log(), print()
- stack traces
- exception handling
- monitoring, telemetry
- audit logs

Detect every case where sensitive data could appear in clear text, including when a whole object is passed to the logger (request, response, config, HTTP error with its headers).

Examples to detect:

BAD

```
Authorization: Bearer eyJ...
token=eyJ...
password=Secret123
client_secret=abcd1234
refresh_token=xxxxx
mongodb://user:password@host
```

GOOD

```
Authorization: Bearer [REDACTED]
token=[REDACTED]
password=[REDACTED]
client_secret=[REDACTED]
mongodb://user:[REDACTED]@host
```

# Step 3: Check masking mechanisms

Check whether sanitization mechanisms exist.

Look for:

- redact()
- sanitize()
- mask()
- scrub()
- filtering middleware
- logging interceptors
- custom serializers
- logger redaction options (lists of masked fields)

Determine:

- which data is masked;
- which data is not;
- whether masking is systematic;
- whether some errors bypass the mechanism.

Identify every execution path that can display sensitive data in clear text.

# Step 4: Check APIs

For every API, inbound and outbound, check:

- Request logging
- Response logging
- Error responses
- Validation errors
- Exception payloads

Detect whether:

- tokens are returned to the client;
- secrets appear in responses;
- errors reveal internal information;
- stack traces can be displayed;
- secrets are passed in a URL (query string), where they end up in proxy logs.

# Step 5: Check error handling

Analyse:

- try/catch
- global exception handlers
- error-handling middleware
- fallback handlers

Detect cases where an exception could expose:

- credentials;
- payloads;
- header contents;
- full requests;
- user data.

# Step 6: Check configuration

Analyse:

- .env.example
- **every real `.env*` file tracked by git** (`git ls-files | grep -i env`), not only the examples
- environment variables
- Helm charts, values per environment
- Kubernetes manifests (Secret vs ConfigMap: a secret in a ConfigMap is a finding)
- Dockerfiles, docker-compose
- CI/CD: GitHub Actions, GitLab CI, Jenkins
- test files, fixtures and snapshots

Detect:

- hard-coded secrets;
- variables printed in logs;
- secrets written to build artifacts;
- secrets propagated to jobs;
- disabled security options (TLS verification, for example `NODE_TLS_REJECT_UNAUTHORIZED=0`);
- real secrets in tests or fixtures.

# Step 7: Git history

A secret removed from the code is still in the history.

- Scan the history (`git log -p`, or better gitleaks/trufflehog in history mode).
- For each secret found in the history: commit, file, date, and whether it is still present in the current version.
- A secret present in the history must be treated as compromised: the recommendation is rotation, not only removal.

# Step 8: Check observability

Analyse:

- Datadog
- Splunk
- Elastic
- OpenTelemetry
- Prometheus
- Grafana
- Sentry
- App Insights
- Dynatrace

Check that telemetry does not collect:

- passwords;
- tokens;
- sensitive payloads;
- authentication headers;
- application secrets;
- personal data.

# Step 9: AI agents and tooling

AI agents and tools are a recent source of leaks. Analyse:

- agent working folders (for example `.scratch/`, `.pi/`, `.claude/`, `.cursor/`, session logs);
- committed prompts, briefs and agent reports;
- instruction files (AGENTS.md, model and provider configuration).

Detect:

- environment values or secrets copied into a report or a prompt;
- LLM provider API keys in files tracked by git;
- personal data sent to an external model.

# Step 10: Check workflows

For each workflow:

- Authentication
- Provisioning
- Synchronisation
- Reconciliation
- Password reset
- User creation
- User update
- User deletion
- API calls
- Batch processing

Check that at no point is a secret:

- displayed;
- logged;
- persisted without need;
- transmitted to an unauthorised system.

# Step 11: Proactive search

Search explicitly (case-insensitive) for:

- Bearer
- Authorization
- Token
- Secret
- Password, passwd, pwd
- Credential
- Key, apikey, api_key
- Cookie
- Session
- Jwt
- OAuth
- Basic Auth
- Client Secret
- Refresh Token
- `://` followed by `:` and `@` (credentials in a URL)
- `BEGIN` + `PRIVATE KEY`

Then analyse every occurrence.

# Expected report

Audited branch and commit: ...
Scanners used: ...

## Executive Summary

- Overall security level
- Critical risks
- High risks
- Moderate risks
- Secrets to rotate immediately (without their values)

## Sensitive Data Inventory

For each piece of sensitive data:

- Source
- Usage
- Storage
- Transmission
- Protection

## Findings

For each finding:

- ID
- Severity (Critical / High / Medium / Low)
- Confidence (CONFIRMED / PROBABLE / NEEDS VERIFICATION)
- Data type concerned
- File and line
- Function
- Evidence (without the secret value)
- Present in the current version, in the history, or both
- Impact
- Recommendation

## Missing Protections

List everything that should be masked but is not.

Example:

CRITICAL

Bearer token logged in clear text in logger.error()

Current:
`Authorization: Bearer eyJh… (212 characters)`

Expected:
`Authorization: Bearer [REDACTED]`

## Secure Coding Recommendations

Give concrete remediation recommendations, in priority order. For any exposed secret (code, history, logs), the first recommendation is rotation.

## Out of Scope Observations

One line per security issue outside this scope that you came across.

## Unknowns

What could not be verified from the repository (production configuration, log tooling, access).
