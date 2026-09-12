# Architecture

> **Status:** Complete at v1.0

## Request Lifecycle

Every wrapped call passes through the same chain. There is no bypass path:

```
Agent tool call
      |
      v
SchemaValidator  -> BLOCK? (unknown keys, missing required, type mismatch)
      |
      v
AccessGate (WITH USER_MODE) -> BLOCK? (CRUD/FLS, profile/permset scoping)
      |
      v
RateLimiter (Platform Cache) -> THROTTLE? (sliding window)
      |
      v
RollbackGuard opens Savepoint + record ceiling
      |
      v
Business logic (your code, unchanged)
      |
      v
AuditPublisher -> AgentGuard_Audit__e Platform Event (async, survives rollback)
```

## Components

| Component             | Responsibility                                                                                                             |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `AgentGuard.cls`      | Public `wrap()` facade; catches gate exceptions as BLOCK (ADR-002); provides `wrapAndExecute()` for auto-rollback          |
| `SchemaValidator.cls` | Validates payload against declared JSON schema contract; rejects unknown keys, enforces required fields and types          |
| `AccessGate.cls`      | CRUD/FLS enforcement in running-user context; `Security.stripInaccessible()` on read paths; profile/permission set scoping |
| `RateLimiter.cls`     | Sliding-window per-user/per-action throttle using Platform Cache; fail-open-with-flag on cache outage                      |
| `RollbackGuard.cls`   | Savepoint boundary + max-records-affected ceiling; auto-rollback on exception via callback                                 |
| `AuditPublisher.cls`  | Publishes `AgentGuard_Audit__e` Platform Event per decision; includes payload hash, latency, gate name                     |

## Data Flow

```
Input: policyName (Guard_Policy__mdt DeveloperName) + payloadJson (String)

1. PolicyRegistry.resolve(policyName)
   - Test override? -> return test policy
   - Metadata cache hit? -> return cached policy
   - SOQL query Guard_Policy__mdt -> hydrate GuardPolicy -> cache -> return
   - Not found? -> return GuardPolicy.disabled(name) (fail closed)

2. SchemaValidator.validate(policy, payloadJson)
   - Parse JSON -> validate against schema contract -> ALLOW or BLOCK

3. AccessGate.evaluate(policy, payloadJson)
   - Check profile/permset scoping -> check CRUD/FLS via Security.stripInaccessible() -> ALLOW or BLOCK

4. RateLimiter.checkLimit(policy, actionName)
   - Get timestamps from Cache.Org partition -> clean expired -> count -> ALLOW, THROTTLE, or ALLOW_FLAGGED

5. RollbackGuard.open(policy, payloadJson)
   - Count records in payload -> if <= maxRecordsPerCall -> setSavepoint() -> attach to ALLOW result

6. AgentGuard.wrap() returns GuardResult
   - If ALLOW: caller proceeds with business logic
   - If BLOCK/THROTTLE: caller throws BlockedException

7. On exception in business logic:
   - Caller calls AgentGuard.rollback(result) OR uses wrapAndExecute()
   - RollbackGuard.rollback() -> Database.rollback(savepoint) -> ROLLBACK result

8. AuditPublisher.publish(AuditContext)
   - Async Platform Event with: policyName, actionName, gateName, decision, reason, payloadHash, latencyMs, flagged, actorId
```

## Key Decisions (ADRs)

- **ADR-001:** Platform Events over custom object for audit — survives rollback.
- **ADR-002:** Fail closed — any internal exception is a BLOCK, never an ALLOW.
- **ADR-003:** Custom Metadata Types over Custom Settings — policy changes ride the same review pipeline as code.
- **ADR-004:** Single `wrap()` facade — "integrated correctly" == "integrated at all".
- **ADR-005:** MIT license.

## Performance Budget (per AgentGuard.wrap() call)

| Resource        | Overhead         | Notes                                            |
| --------------- | ---------------- | ------------------------------------------------ |
| SOQL Queries    | 1–2              | Policy lookup + optional FLS describe cache miss |
| DML Statements  | 0                | Only Savepoint, no DML in gate path              |
| CPU Time        | 2–6 ms           | Schema validation reflection + FLS checks        |
| Heap Size       | <10 KB           | Payload processed as deserialized map            |
| Platform Cache  | 1 read + 1 write | Rate limiter; falls back to allow-and-log        |
| Platform Events | 1 publish        | Async; doesn't consume sync DML limits           |

For bulk invocable calls (200 records), overhead stays flat — one policy lookup and one rate-limit check per action.

## Security Model

- **Fail closed everywhere**: Uncertain paths BLOCK, never ALLOW
- **Running user context**: All checks use `WITH USER_MODE` / `Security.stripInaccessible()` — never elevated
- **Audit survives rollback**: Platform Events publish outside transaction boundary
- **No external callouts**: Core enforcement path has zero network dependencies (LIMITS.md)
- **Restrictive by default**: Every policy knob defaults to BLOCK/THROTTLE/zero
