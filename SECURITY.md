# Security Policy

AgentGuard SF is a security tool — vulnerability reports are treated as the highest
priority work in this repository. Thank you for taking the time to disclose
responsibly.

## Supported Versions

| Version | Supported                                            |
| ------- | ---------------------------------------------------- |
| < 1.0.0 | Pre-release development — report against `main` only |

## How to Report a Vulnerability

**Do NOT open a public GitHub issue, PR, or discussion for a suspected
vulnerability.**

Report privately via **GitHub Security Advisories**
(Repository → Security → Report a vulnerability), which notifies the maintainer
directly and keeps the report confidential until a fix ships.

Include, where possible:

- Affected component (`SchemaValidator`, `AccessGate`, `RateLimiter`, `RollbackGuard`,
  `AuditPublisher`, packaging metadata)
- A minimal reproduction (payload + policy config + expected vs actual decision)
- Impact assessment: what data could be read/mutated, and under what user context
- Any known workaround

## Response Targets

| Stage                               | Target   |
| ----------------------------------- | -------- |
| Acknowledgement                     | 72 hours |
| Triage & severity assignment        | 7 days   |
| Fix or mitigation for High/Critical | 30 days  |

If you receive no response within these targets, escalate by opening an issue that
says only "please check Security Advisories inbox" — never include details publicly.

## Scope

In scope: anything in the enforcement path — gate bypass, fail-open behavior,
CRUD/FLS circumvention, rollback boundary violation, audit suppression,
policy-default weakening, package supply-chain issues.

Out of scope (see [LIMITS.md](LIMITS.md)): semantic prompt-injection detection,
Einstein Trust Layer functionality, identity/infrastructure controls (Dev Hub
compromise, credential theft), long-term audit retention.

## Disclosure Policy

- Fixes are developed on `sec/*` branches with restricted discussion.
- Credit is given to reporters in the release notes unless anonymity is requested.
- A CVE will be requested for vulnerabilities affecting released versions.

## Design Baseline

The project fails closed by design (ADR-002): any exception inside a gate is a
BLOCK. If you find any code path where an internal error can produce an ALLOW,
that is a critical-severity bug.
