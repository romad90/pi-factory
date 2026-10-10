# Study: sandboxing agents

**Last reviewed:** 2026-10-10 · **Next review:** 2027-01 (quarterly, by a scheduled task that updates this file and opens a PR) · **Status of the recommendation:** level 1 planned for v1.2 (roadmap S8), level 2 as a spike (X14)

Agents run with bash on a laptop, with the owner's identity. Since v1.1 the factory has a deny-list (command guard) and a deterministic patch check (patch guard). This study looks at the next step: **"only this is allowed"**, enforced by the OS or by a hardware boundary. Scope: lightweight, local to a macOS or Linux laptop, easy to integrate in a Pi stack. Cloud sandboxes (E2B, Daytona, Modal, Vercel…) are out of scope: the code and history would leave the machine.

## Three levels of isolation

### 1. Process sandbox enforced by the OS: `sandbox-runtime` (srt)

- **What:** Anthropic's open-source tool (Apache-2.0), built for Claude Code. Wraps any command: Seatbelt (`sandbox-exec`) on macOS, bubblewrap with no network namespace on Linux.
- **Enforces:** writes denied except listed paths; network denied by default, allowed per domain through a host proxy (which also refuses allowed names resolving to loopback, link-local or metadata addresses); reads denied on chosen paths (`~/.ssh`, `.env`).
- **Pi:** an official Pi example extension wraps commands with it, with per-project config.
- **Scope:** wraps the commands agents run, not the Pi process; model calls are unaffected.
- **Limits:** same kernel (userspace control); "Beta Research Preview"; Linux path globs narrower than macOS; a reported case of a bubblewrap denylist bypass in Claude Code shows the ceiling of this level.

### 2. One micro-VM per agent, Pi-native: Gondolin

- **What:** by Earendil (Pi's authors). Micro-VMs with QEMU by default, libkrun experimental; macOS and Linux; boot under a second. A Pi example extension routes built-in tools and `!` commands into the VM.
- **Enforces:** only mounted folders visible (`/workspace`), disposable root (read-only, memory or copy-on-write); egress allowlist with HTTP/TLS hooks; outbound SSH filtered; controlled DNS.
- **Secrets:** the guest only sees placeholders; the host substitutes the real value only for requests to hosts on that secret's allowlist, blocks the rest. An agent can't leak a token it never sees.
- **Limits:** young (krun backend experimental, pre-release parts); one image per repo with its toolchain; FUSE file access may slow heavy test suites; QEMU or virtualization may need IT approval.
- **Same level, open source:** microsandbox (libkrun, Apache-2.0, fine network control, host-side secret injection; needs a daemon, v0.3, breaking changes expected). BoxLite (libkrun-like, embedded library, no fine network control).

### 3. The whole mission in a micro-VM: Docker Sandboxes (`sbx`)

- **What:** micro-VMs (not containers) created when an agent starts, each with its own Docker daemon; network presets Open / Balanced / Locked Down, per project, with a network log; credentials injected by a host proxy.
- **Pi:** supported through a custom image.
- **Enables:** lead and subagents running unattended inside the VM: the closest thing today to Step 3.
- **Limits:** not open source (announced free, licence not final); no way yet to hide a single file such as `.env`; one VM per project to keep updated; IDE stays on the host.

## Threat coverage

| Threat | v1.1 (command + patch guard) | 1. srt | 2. Gondolin | 3. Docker Sandboxes |
|---|---|---|---|---|
| Destructive command outside the repo | deny-list | writes only in the worktree | disposable VM root | separate VM |
| Exfiltration of code or data | deny-list | network denied except allowlist | allowlist + HTTP hooks | presets + log |
| Credential theft | deny-list on paths | reads denied | never visible (placeholders) | proxy; `.env` still visible |
| Malicious dependency script (`postinstall`) | not covered | contained | contained | contained |
| Worker reading the hidden instrument | soft | reads denied | hard (never mounted) | hard if not mounted |
| Kernel flaw / escape | not covered | not covered | covered (hypervisor) | covered |
| Prompt injection via repo content | limits damage | limits damage | limits more | limits more |

Prompt injection is never prevented, only contained; the isolation level decides how much.

## Impact on the factory

- **Stays:** the command guard (it tells the agent *why* and makes it stop and ask), the patch guard (protects the repo: a patch that skips a test is "legal" inside any sandbox), the gates.
- **Adds:** one extension and one config generated from `.factory/commands.env` (gateway and package registry domains); a doctor check. No new role.
- **Model quota:** no effect at any level. **Time:** negligible (1); under a second per worker plus slower file I/O (2); one VM per mission (3).
- **Company laptop:** Seatbelt is built into macOS (1); QEMU or virtualization to get approved (2); a Docker product with an unfinished licence to get approved (3). Show the options to the security team before investing: isolation is likely a prerequisite for unattended missions.

## Hands-on validation

| Machine | Result | Notes |
|---|---|---|
| macOS laptop (2026-10-10) | **Works.** Allowed domain goes through the srt proxy; other domains get `403` with `X-Proxy-Error: blocked-by-allowlist`; `~/.ssh` reads denied (`Operation not permitted`); writes in the allowed folder work; writes outside it (home folder) denied (`Operation not permitted`). All four checks pass. | Native Seatbelt, only `npm install -g @anthropic-ai/sandbox-runtime`. Run commands as `srt -c "<command>"`: a quoted string without `-c` is taken as one program name and fails with "No such file or directory". |
| Cloud dev workspace (Linux container in Kubernetes, Debian 12) | **Not available yet.** `socat` and `rg` present, `bwrap` absent, no sudo. User namespaces (needed by bubblewrap) to confirm with `unshare --user --map-root-user true`; usually blocked in pods. A Kubernetes service account token is mounted under `/var/run/secrets`. | The "VM" is a container: the platform is the isolation boundary. What matters there is what it reaches (internal network, mounted token, Git credentials). The command guard now blocks reads of mounted secrets (PR #11). Until bubblewrap and user namespaces are available: `FACTORY_SANDBOX=off` on this machine, recorded with that reason; sandboxed missions run from the laptop. |

**Optional per machine (design for S8):** a machine-level setting `FACTORY_SANDBOX=srt|off` (the repo stays the same everywhere; allowed domains come from `commands.env`). Default `srt` where the pre-flight finds it working; `off` only as a recorded decision with a reason; the metrics and the MR state the level used; required once missions run unattended (Step 3).

## Recommendation

1. **v1.2: level 1 for every command agents run** (roadmap S8). Turns "we hope the deny-list is complete" into "only this is allowed", for close to zero cost.
2. **Missions 3–4: Gondolin spike on one or two workers** (roadmap X14). Measure test time in the VM, get the security team's view. If it holds, it becomes the worker standard, and secret placeholders answer "the agent has my identity".
3. **Step 3: the whole mission isolated** (S5, X13): Docker Sandboxes or Pi Durable execution environments, decided then on maturity and what the company accepts.

## How this study is refreshed

Quarterly, a scheduled task re-scans the field (new tools, maturity changes, licences, macOS support, reported bypasses), updates this file with a dated changelog entry, and opens a `docs:` PR into `develop`. A human reviews it; a change of recommendation becomes an ADR decision.

## Sources

- [Anthropic sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- [Pi extension examples (sandbox, gondolin)](https://unpkg.com/@earendil-works/pi-coding-agent@0.83.0/examples/extensions/README.md)
- [Gondolin documentation (index)](https://docsearch.algolia.com/mcp/docs/repo/earendil-works/gondolin)
- [Your Container Is Not a Sandbox: The State of MicroVM Isolation in 2026](https://emirb.github.io/blog/microvm-2026/)
- [Microsandbox vs BoxLite](https://www.paperclipped.de/en/blog/microsandbox-boxlite-ai-agent-sandboxes/)
- [Trust, but sandbox (INNOQ, Docker Sandboxes)](https://www.innoq.com/en/blog/2026/07/trust-but-sandbox/)
- [awesome-agent-sandbox](https://github.com/fishman/awesome-agent-sandbox)

## Changelog

- 2026-10-10: first study; srt fully validated on macOS (network, reads, writes); not available in the container workspace yet; per-machine option designed for S8.
