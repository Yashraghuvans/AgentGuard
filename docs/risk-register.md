# Known Limitations & Risk Register

> **Status:** living document. Add a row the moment a limitation is discovered,
> even before a fix ships — a maintained risk register is more credible than one
> describing only a finished, perfect system.

| Limitation | Why it exists | Recommended mitigation today |
| --- | --- | --- |
| No semantic / NLP-level prompt-injection detection | Enforcement is structural (schema, CRUD/FLS, rate, rollback), not a content classifier — see LIMITS.md | Pair with Einstein Trust Layer masking/grounding at the prompt boundary |
| RateLimiter state resets on Platform Cache eviction/outage | Platform Cache is not guaranteed persistent across org events | Mirror counters into durable storage for strict compliance needs (roadmap item); cache-outage fallback is allow-and-log with flagged event |
| No cross-org / multi-org policy sync in v1 | Policies are per-org metadata, deployed like any other metadata | Use CI/CD to deploy identical `Guard_Policy__mdt` records consistently |
| Does not defend against compromised Dev Hub / deployment credentials | Application-layer control, not identity/infrastructure control | Standard DevOps hygiene: MFA on Dev Hub, scoped connected apps, secret rotation |
| Audit event visibility can lag seconds under platform load | Platform Event delivery is at-least-once, async in some contexts | BLOCK decisions remain synchronous and enforced before DML regardless of dashboard lag |
| Bug in AgentGuard itself blocks legitimate calls until patched | Deliberate fail-closed design (ADR-002) | Preferred over silently allowing unvalidated calls; patch releases prioritize gate bugs |
