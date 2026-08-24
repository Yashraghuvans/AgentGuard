# LIMITS.md

Explicit scope limits — what this project deliberately does **not** attempt, and
why. Prevents scope creep and sets honest expectations for adopters. Additions here
require an ADR (see `CHANGELOG.md` / `docs/`).

## Not Attempted (v1)

- **Not a replacement for Salesforce's Einstein Trust Layer.**
  AgentGuard does not mask data sent to an external LLM. It governs actions *after*
  the LLM decides to call a tool. Pair them: Trust Layer at the prompt boundary,
  AgentGuard at the action boundary.

- **Not a general-purpose Apex security scanner.**
  It only governs calls that explicitly opt in via `AgentGuard.wrap()`. Unwrapped
  Apex gets nothing.

- **No cross-org or multi-org policy sync in v1.**
  Policies are per-org, configured via metadata deployment. Use your CI/CD pipeline
  to deploy identical `Guard_Policy__mdt` records across environments.

- **No semantic / NLP-level prompt-injection detection.**
  Enforcement is structural (schema, CRUD/FLS, rate, rollback) — not a content
  classifier. A well-formed payload that happens to be malicious-but-valid still
  needs your org's data model and permissions to constrain it.

- **Not an identity or infrastructure control.**
  It does not defend against a compromised Dev Hub, deployment credential, or
  compromised admin session. Use standard Salesforce DevOps hygiene (MFA, scoped
  connected apps, secret rotation) for those layers.

- **Not a long-term audit store.**
  Audit output is a Platform Event stream (ADR-001). Teams needing queryable,
  retained audit history must subscribe and persist events into a custom object or
  external SIEM themselves.

- **Rate limiting is best-effort persistence.**
  Counters live in Platform Cache and may reset on cache eviction/outage. Strict
  compliance needs should mirror counters into durable storage (roadmap item).

## Honest Failure Modes

- A bug in AgentGuard itself blocks legitimate calls until patched (fail-closed,
  ADR-002). This degradation is deliberate: availability suffers before security does.
- During a Platform Cache outage the rate limiter falls back to allow-and-log with
  a flagged event rather than silently pretending throttling is active.
