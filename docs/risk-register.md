# Known Limitations & Risk Register

> **Status:** Living document. Add a row the moment a limitation is discovered, even before a fix ships — a maintained risk register is more credible than one describing only a finished, perfect system.

## Risk Register

| ID     | Limitation                                                                        | Why It Exists                                                                                          | Recommended Mitigation Today                                                                                                                          | Status     |
| ------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| RL-001 | No semantic / NLP-level prompt-injection detection                                | Enforcement is structural (schema, CRUD/FLS, rate, rollback), not a content classifier — see LIMITS.md | Pair with Einstein Trust Layer masking/grounding at the prompt boundary                                                                               | Accepted   |
| RL-002 | RateLimiter state resets on Platform Cache eviction/outage                        | Platform Cache is not guaranteed persistent across org events                                          | Mirror counters into durable custom object for strict compliance (roadmap); cache-outage fallback is allow-and-log with `Flagged__c=true` audit event | Accepted   |
| RL-003 | No cross-org / multi-org policy sync in v1                                        | Policies are per-org metadata, deployed like any other metadata                                        | Use CI/CD pipeline to deploy identical `Guard_Policy__mdt` records consistently across sandboxes/production                                           | Roadmap    |
| RL-004 | Does not defend against compromised Dev Hub / deployment credentials              | Application-layer control, not identity/infrastructure control                                         | Standard DevOps hygiene: MFA on Dev Hub, scoped connected apps, secret rotation                                                                       | Accepted   |
| RL-005 | Audit event visibility can lag seconds under platform load                        | Platform Event delivery is at-least-once, async in some contexts                                       | BLOCK decisions remain synchronous and enforced before DML regardless of dashboard lag                                                                | Accepted   |
| RL-006 | Bug in AgentGuard itself blocks legitimate calls until patched                    | Deliberate fail-closed design (ADR-002)                                                                | Preferred over silently allowing unvalidated calls; patch releases prioritize gate bugs                                                               | Accepted   |
| RL-007 | SchemaValidator doesn't support nested object validation beyond one level         | Current implementation validates flat properties only                                                  | Flatten payloads; nested object support on roadmap                                                                                                    | Roadmap    |
| RL-008 | RateLimiter per-user only; no org-level budget                                    | Per-agent scoping by design; org-level requires aggregate view                                         | Add org-level budget via scheduled job aggregating per-user counts (roadmap)                                                                          | Roadmap    |
| RL-009 | No built-in alerting on throttle/block spikes                                     | AgentGuard publishes events; alerting is consumer responsibility                                       | Subscribe to `AgentGuard_Audit__e` and build alerts in Flow/Apex/External                                                                             | Roadmap    |
| RL-010 | Audit events not queryable via standard SOQL                                      | Platform Events are stream-based, not standard objects                                                 | Subscribe via trigger and persist to custom object for reporting                                                                                      | Accepted   |
| RL-011 | Platform Cache partition capacity limits max concurrent users                     | Org Cache partition has fixed capacity (default 10MB)                                                  | Monitor Cache.Org usage; increase partition size; implement cache warming                                                                             | Monitoring |
| RL-012 | `AllowedProfiles__c` / `AllowedPermissionSets__c` are semicolon-delimited strings | Custom Metadata Type doesn't support multi-picklist or relationship fields                             | Parse in `PolicyRegistry`; consider custom object for complex scoping (roadmap)                                                                       | Accepted   |
| RL-013 | No support for polymorphic field references in schema                             | SchemaValidator validates known types only                                                             | Document as limitation; avoid polymorphic fields in wrapped actions                                                                                   | Accepted   |
| RL-014 | RollbackGuard max-records counts payload items, not DML rows                      | Payload may not 1:1 map to DML rows (e.g., one payload → multiple DML)                                 | Set conservative `MaxRecordsPerCall__c`; implement custom counting in business logic if needed                                                        | Accepted   |

## Risk Assessment Methodology

Each risk is assessed on:

- **Likelihood**: How likely the limitation manifests in production
- **Impact**: Security/availability impact if exploited
- **Mitigation Cost**: Effort to implement recommended mitigation
- **Decision**: Accepted / Roadmap / Monitoring

## Adding New Risks

When a new limitation is discovered:

1. Add a row to this table in the same PR
2. Assign next RL-XXX ID
3. Classify as Accepted / Roadmap / Monitoring
4. Link to any related GitHub issue

## Review Cadence

- **Per release**: Review all risks; update status
- **Per security incident**: Add relevant risk if not present
- **Quarterly**: Re-assess likelihood/impact for accepted risks
