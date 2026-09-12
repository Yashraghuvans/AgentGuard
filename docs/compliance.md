# Compliance Framework Mapping

> **Status:** Complete at v1.0.

## Important Caveat

**This mapping shows how AgentGuard's controls contribute evidence toward these frameworks. It is NOT a certification and does not by itself make an org compliant.** Do not overclaim. AgentGuard is a technical control library; compliance requires organizational processes, policies, and additional controls.

## Framework Mappings

| Framework / Control Area                       | Relevant Requirement                                                                               | How AgentGuard Helps                                                                                                            |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **SOC 2 — CC6 (Logical Access)**               | Access to systems and data is restricted to authorized users and processes                         | `AccessGate` enforces CRUD/FLS per running user on every AI-originated call, not just human-originated ones                     |
| **SOC 2 — CC7 (System Monitoring)**            | The entity monitors system components for anomalies indicative of malicious acts                   | `RateLimiter` flags anomalous call volume; every decision is published as a real-time, queryable audit event                    |
| **SOC 2 — CC8 (Change Management)**            | Changes to infrastructure, data, software are controlled                                           | Policy changes via `Guard_Policy__mdt` require metadata deployment through CI/CD pipeline (ADR-003)                             |
| **GDPR — Art. 5(2) (Accountability)**          | Controllers must be able to demonstrate compliance with data-processing principles                 | `AuditPublisher` provides a durable, timestamped record of every data-mutating action an AI agent attempted, allowed or blocked |
| **GDPR — Art. 25 (Data Protection by Design)** | Technical measures must implement data-protection principles by default                            | Restrictive-by-default policy posture — nothing is permitted unless explicitly configured                                       |
| **GDPR — Art. 32 (Security of Processing)**    | Implement appropriate technical measures                                                           | CRUD/FLS enforcement, rate limiting, atomic rollback, audit logging                                                             |
| **GDPR — Art. 28 (Processor Contracts)**       | Processor provides sufficient guarantees                                                           | AgentGuard is open-source (MIT); source auditable; no external callouts in core path                                            |
| **HIPAA — 164.312(a)(1) (Access Control)**     | Technical policies limiting access to authorized persons/programs                                  | `AccessGate` + `Guard_Policy__mdt` profile/permset scoping restrict which agents/actions can touch which fields                 |
| **HIPAA — 164.312(b) (Audit Controls)**        | Hardware, software, procedural mechanisms to record and examine activity in systems containing PHI | Every AI-driven touch of a PHI-bearing object routed through AgentGuard is captured in the audit event stream                   |
| **HIPAA — 164.312(c)(1) (Integrity)**          | Protect ePHI from improper alteration or destruction                                               | `RollbackGuard` Savepoint boundary ensures atomic mutations; partial failures roll back completely                              |
| **HIPAA — 164.312(d) (Person Authentication)** | Verify identity of persons/programs                                                                | Relies on Salesforce platform authentication; `AccessGate` evaluates running user context                                       |
| **ISO 27001 — A.9 (Access Control)**           | Access control policy, user access management                                                      | `AccessGate` enforces per-call CRUD/FLS; policies define scoping via profiles/permsets                                          |
| **ISO 27001 — A.12 (Operations Security)**     | Logging, monitoring, vulnerability management                                                      | `AuditPublisher` + `RateLimiter` provide operational visibility and anomaly detection                                           |
| **ISO 27001 — A.14 (Secure Development)**      | Security requirements in development                                                               | Gate chain enforced at code level; CI pipeline enforces 90% coverage, PMD security rules                                        |

## Evidence Artifacts for Auditors

| Artifact                      | Location                       | Purpose                                     |
| ----------------------------- | ------------------------------ | ------------------------------------------- |
| Threat Model                  | `docs/threat-model.md`         | STRIDE analysis with component mitigations  |
| Architecture Decision Records | `docs/architecture.md`         | ADR-001 through ADR-005                     |
| Policy Configuration          | `docs/policy-configuration.md` | Field reference with restrictive defaults   |
| Test Coverage Matrix          | `docs/testing.md`              | Each threat → automated test mapping        |
| CI Pipeline                   | `.github/workflows/ci.yml`     | Lint, static analysis, test, coverage gates |
| Risk Register                 | `docs/risk-register.md`        | Known limitations and mitigations           |
| CHANGELOG                     | `CHANGELOG.md`                 | Versioned release history                   |

## What AgentGuard Does NOT Provide

| Control Area                 | Gap          | Recommended Mitigation                                                |
| ---------------------------- | ------------ | --------------------------------------------------------------------- |
| Data encryption at rest      | Out of scope | Salesforce Shield Platform Encryption                                 |
| Data masking for LLM prompts | Out of scope | Einstein Trust Layer                                                  |
| Identity verification / MFA  | Out of scope | Salesforce Identity / MFA settings                                    |
| Network segmentation         | Out of scope | Salesforce My Domain, IP restrictions                                 |
| Vulnerability scanning       | Partial      | CI includes PMD security rules; add CodeQL, dependency scanning       |
| Incident response plan       | Out of scope | Organizational process                                                |
| Data retention / disposal    | Partial      | Platform Event 72-hr retention; subscribe to custom object for longer |

## Using This Mapping

When responding to compliance questionnaires or audits:

1. **Reference this document** as evidence of technical controls
2. **Point to the threat model** for risk assessment methodology
3. **Show the CI pipeline** for continuous enforcement evidence
4. **Demonstrate test coverage** matrix linking threats to automated tests
5. **Disclose limitations** from [LIMITS.md](/context/LIMITS.md) and [Risk Register](risk-register.md) honestly

## Versioning

This mapping is versioned with the AgentGuard release. Check `CHANGELOG.md` for changes to controls that affect compliance posture.
