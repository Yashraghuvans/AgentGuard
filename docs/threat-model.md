# Threat Model (STRIDE)

> **Status:** Complete at v1.0. Maintained per RULES.md #14: updated in the same PR that changes a gate's behavior. A stale threat model is worse than none.

## STRIDE Mapping

| STRIDE                     | Threat in This Context                                                                                                          | Mitigating Component                                                                                                                                      |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Spoofing**               | Agent session impersonates a higher-privileged user context to gain broader data access                                         | `AccessGate` — always evaluates `WITH USER_MODE` against the real running-user context, never a claimed or elevated one                                   |
| **Tampering**              | Prompt-injected instruction reshapes a payload into a bulk or out-of-contract mutation                                          | `SchemaValidator` — rejects any payload not matching the action's declared contract before it reaches business logic                                      |
| **Repudiation**            | An agent (or attacker who compromised it) denies having issued a destructive call, with no record to prove otherwise            | `AuditPublisher` — every decision (ALLOW, BLOCK, THROTTLED, ROLLBACK) is published as an immutable Platform Event with actor, payload hash, and timestamp |
| **Information Disclosure** | An agent queries or returns fields the requesting user is not permitted to see                                                  | `AccessGate` — field-level security enforcement strips or blocks inaccessible fields on read paths via `Security.stripInaccessible()`                     |
| **Denial of Service**      | A misbehaving or manipulated agent floods an action with rapid repeated calls, exhausting governor limits or downstream systems | `RateLimiter` — sliding-window per-agent, per-action throttling with configurable budgets; fail-open-with-flag on cache outage                            |
| **Elevation of Privilege** | A partially-successful bulk mutation leaves the org in an inconsistent state that grants unintended access via side effects     | `RollbackGuard` — Savepoint boundary and max-record ceiling ensure atomic, bounded mutations only                                                         |

## Component-to-Threat Traceability

| Component           | Primary STRIDE                   | Secondary STRIDE                                             |
| ------------------- | -------------------------------- | ------------------------------------------------------------ |
| SchemaValidator     | Tampering                        | Information Disclosure (via schema-enforced field allowlist) |
| AccessGate          | Spoofing, Information Disclosure | Elevation of Privilege (via CRUD enforcement)                |
| RateLimiter         | Denial of Service                | —                                                            |
| RollbackGuard       | Elevation of Privilege           | Tampering (prevents partial commits)                         |
| AuditPublisher      | Repudiation                      | Spoofing (actor ID), Information Disclosure (payload hash)   |
| AgentGuard (Facade) | All (fail-closed boundary)       | —                                                            |

## Attack Scenarios & Mitigations

### Scenario 1: Prompt Injection → Bulk Mutation

**Attack:** LLM instructed to "delete all accounts" → payload shaped as array of 10,000 record IDs
**Mitigation:** `SchemaValidator` rejects unknown keys/structure; `RollbackGuard` enforces `MaxRecordsPerCall__c` ceiling (default 1)

### Scenario 2: Privilege Escalation via Field Injection

**Attack:** Payload includes `OwnerId` or `IsDeleted` fields the running user cannot edit
**Mitigation:** `AccessGate` uses `Security.stripInaccessible(AccessType.UPDATABLE)` — strips or blocks inaccessible fields

### Scenario 3: Rate Limit Bypass via Session Rotation

**Attack:** Attacker rotates user contexts to evade per-user limits
**Mitigation:** Rate limit keyed by `UserInfo.getUserId()` — rotation requires valid auth; consider org-level budget (roadmap)

### Scenario 4: Audit Evasion via Rollback

**Attack:** Malicious call triggers exception → hopes audit rolls back too
**Mitigation:** `AuditPublisher` uses `EventBus.publish()` — Platform Events publish **outside** transaction rollback boundary (ADR-001)

### Scenario 5: Cache Outage → Silent Fail-Open

**Attack:** Platform Cache evicted/cleared → rate limiter stops working
**Mitigation:** `RateLimiter` catches `Cache.CacheException` → returns `ALLOW_FLAGGED` with audit flag; never silently fails open

## Explicit Non-Goals

See [LIMITS.md](/context/LIMITS.md) and [Risk Register](risk-register.md):

- No semantic/NLP-level prompt-injection detection
- Not a replacement for Einstein Trust Layer (operates at different layer)
- Not an identity control — relies on Salesforce auth
- No cross-org policy sync in v1

## Test Coverage Matrix

Each threat row maps to a currently-passing automated test (see [testing.md](testing.md)).

| Threat                                                              | Test Type   | Test Class                                                                                                                         |
| ------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Prompt-injected bulk mutation via single-record action              | Flow        | `TerritoryReassignFlowTest.given_injectedBulkChurnPayload_when_agentInvokes_then_blockedAndAudited()`                              |
| User lacks field-level access to a mutated field                    | Unit        | `AccessGateTest.given_readOnlyUser_when_modifiesAccount_then_blocksWithReason()`                                                   |
| Agent exceeds configured rate limit in rolling window               | Flow        | `TerritoryReassignFlowTest.given_repeatedRapidCalls_when_rateLimitExceeded_then_throttledAfterThreshold()`                         |
| Malformed payload missing required schema field                     | Unit        | `SchemaValidatorTest.given_missingRequiredField_when_validated_then_blocksWithReason()`                                            |
| Partial failure mid-bulk-operation triggers full rollback           | Unit + Flow | `RollbackGuardTest.given_executeWithRollback_when_callbackThrows_then_rollsBackAndReturnsRollback()` + `TerritoryReassignFlowTest` |
| Every BLOCK decision produces exactly one audit event               | Flow        | `AgentGuardTest.given_blockedCall_when_wrapped_then_auditEventIsBlocked()` + `TerritoryReassignFlowTest`                           |
| Bulk payload of 200 records processes without governor-limit errors | Unit        | `AccessGateTest.given_bulkPayload_when_evaluated_then_handles200RecordsWithoutLimitError()`                                        |
| Cache outage triggers allow-and-log (not silent fail-open)          | Unit        | `RateLimiterTest.given_cachePartitionMissing_when_checked_then_allowFlagged()`                                                     |

**CI Enforcement:** Every row in this matrix corresponds to a real, currently-passing test in the GitHub Actions pipeline. An entry with no matching green check is a documentation lie.
