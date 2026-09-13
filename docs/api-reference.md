# API Reference

> **Status:** Complete at v1.0. Generated from ApexDoc headers.

## `AgentGuard` (Facade)

The **only** public entry point. Direct use of gate classes is discouraged (ADR-004).

### `wrap(policyName, payloadJson)`

```apex
public static GuardResult wrap(String policyName, String payloadJson)
```

| Parameter     | Type     | Description                                                        |
| ------------- | -------- | ------------------------------------------------------------------ |
| `policyName`  | `String` | `Guard_Policy__mdt` DeveloperName (or registered test policy name) |
| `payloadJson` | `String` | Raw JSON string representing the invocable request payload         |

**Returns:** `GuardResult` — `ALLOW` with savepoint attached, or `BLOCK`/`THROTTLED`/`ROLLBACK` with reason.

**Behavior:**

1. Resolves policy via `PolicyRegistry`
2. Executes gate chain: SchemaValidator → AccessGate → RateLimiter → RollbackGuard
3. On any gate BLOCK/THROTTLE: publishes audit event, returns immediately
4. On all gates ALLOW: opens Savepoint, attaches to result, publishes ALLOW audit event
5. Any unhandled exception: caught, treated as FACADE BLOCK, audit published

**Example:**

```apex
GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
return TerritoryService.reassign(requests);
```

### `wrapAndExecute(policyName, payloadJson, businessLogic)`

```apex
public static GuardResult wrapAndExecute(
    String policyName,
    String payloadJson,
    RollbackGuard.GuardResultCallback businessLogic
)
```

Convenience method that wraps and executes business logic with automatic rollback on exception.

**Example:**

```apex
GuardResult result = AgentGuard.wrapAndExecute('UpdateAccountTerritory', JSON.serialize(reqs),
    new RollbackGuard.GuardResultCallback() {
        public GuardResult execute(GuardResult allow) {
            return TerritoryService.reassign(reqs);
        }
    }
);
```

### `rollback(result)`

```apex
public static GuardResult rollback(GuardResult result)
```

Rolls back to the savepoint attached to an ALLOW result. Call from catch block when business logic throws.

**Returns:** `GuardResult` with `decision = ROLLBACK`.

### `BlockedException`

```apex
public class BlockedException extends Exception {
  public String decision;
  public String gateName;
}
```

Thrown by callers when `GuardResult.isAllowed == false`. Contains the decision and gate name for programmatic handling.

---

## `GuardResult`

Immutable value type returned by every gate and the facade.

### Fields

| Field            | Type        | Description                                                                           |
| ---------------- | ----------- | ------------------------------------------------------------------------------------- |
| `isAllowed`      | `Boolean`   | `true` only when `decision == ALLOW`                                                  |
| `decision`       | `String`    | `ALLOW` \| `BLOCK` \| `THROTTLED` \| `ROLLBACK`                                       |
| `reason`         | `String`    | Human-readable reason; **always populated for non-ALLOW**                             |
| `policyName`     | `String`    | Policy DeveloperName evaluated                                                        |
| `actionName`     | `String`    | Action name supplied to `wrap()`                                                      |
| `gateName`       | `String`    | Gate that produced decision: `FACADE` \| `SCHEMA` \| `ACCESS` \| `RATE` \| `ROLLBACK` |
| `flagged`        | `Boolean`   | `true` when ALLOW carries degraded-mode flag (e.g., cache outage)                     |
| `savepointToken` | `Savepoint` | (Internal) Attached by RollbackGuard; accessed via `getSavepoint()`                   |

### Factory Methods

```apex
// ALLOW with default reason
GuardResult.allow(String policy, String action)

// ALLOW with degraded-mode flag and reason
GuardResult.allowFlagged(String policy, String action, String reason)

// BLOCK from specific gate
GuardResult.block(String gate, String policy, String action, String reason)

// THROTTLED from RateLimiter
GuardResult.throttled(String policy, String action, String reason)

// ROLLBACK after rollback
GuardResult.rolledBack(String policy, String action, String reason)
```

**Invariant:** `block()`, `throttled()`, `rolledBack()` throw `IllegalArgumentException` if `reason` is blank.

---

## `GuardPolicy`

Immutable domain wrapper for `Guard_Policy__mdt`.

### Fields

| Field                    | Type          | Description                                   |
| ------------------------ | ------------- | --------------------------------------------- |
| `policyName`             | `String`      | Policy DeveloperName                          |
| `isEnabled`              | `Boolean`     | Master kill-switch                            |
| `targetSObjectType`      | `String`      | Target sObject API name                       |
| `operation`              | `Operation`   | `READ` \| `CREATE` \| `MODIFY` \| `REMOVE`    |
| `schemaContractJson`     | `String`      | JSON schema contract                          |
| `maxRecordsPerCall`      | `Integer`     | Record ceiling (0 = block)                    |
| `rateLimitPerMinute`     | `Integer`     | Invocation budget (0 = throttle)              |
| `rateLimitWindowSeconds` | `Integer`     | Sliding window length (clamped to [10, 3600]) |
| `allowedProfiles`        | `Set<String>` | Profile names allowed                         |
| `allowedPermissionSets`  | `Set<String>` | Permission set names allowed                  |

### Fluent Builder

```apex
GuardPolicy.disabled('ActionName')
    .withEnabled(true)
    .withSObjectType('Account')
    .withOperation(GuardPolicy.Operation.MODIFY)
    .withSchemaContract('{"properties":{...}}')
    .withMaxRecordsPerCall(5)
    .withRateLimit(10)
    .withRateLimitWindowSeconds(60)
    .withAllowedProfiles(new Set<String>{ 'Agentforce Service Agent' })
    .withAllowedPermissionSets(new Set<String>{ 'Agent_Tools' });
```

**Restrictive defaults:** Every `with*` method treats `null` as the most restrictive value.

---

## `SchemaValidator`

```apex
public static GuardResult validate(GuardPolicy policy, String payloadJson)
```

Validates payload against policy's `schemaContractJson`. Returns `ALLOW` or `BLOCK` (gate: `SCHEMA`).

**Validation rules:**

- Rejects unknown top-level keys (fail closed)
- Enforces required fields
- Validates types: string, integer, number, boolean, array, object
- Supports `nullable`, `minimum`, `maximum`, `enum` constraints

---

## `AccessGate`

```apex
public static GuardResult evaluate(GuardPolicy policy, String payloadJson)
public static List<GuardResult> evaluateBulk(GuardPolicy policy, List<Map<String, Object>> payloads)
```

Enforces CRUD/FLS in running user context. Returns `ALLOW` or `BLOCK` (gate: `ACCESS`).

**Checks:**

1. Policy enabled?
2. Profile scoping (`AllowedProfiles__c`)
3. Permission set scoping (`AllowedPermissionSets__c`)
4. Object-level CRUD (createable/updateable/deletable per operation)
5. Field-level security via `Security.stripInaccessible()`

---

## `RateLimiter`

```apex
public static GuardResult checkLimit(GuardPolicy policy, String actionName)
```

Sliding-window throttle using Platform Cache (`Cache.Org` partition `AgentGuard`). Returns `ALLOW`, `THROTTLED`, or `ALLOW_FLAGGED` (gate: `RATE`).

**Behavior:**

- Key: `ratelimit_<userId>_<actionName>`
- Cleans expired timestamps before counting
- On cache outage: `ALLOW_FLAGGED` with reason `RATE_LIMIT_CACHE_ERROR` or `RATE_LIMIT_CACHE_PARTITION_MISSING`
- Window clamped to [10, 3600] seconds

---

## `RollbackGuard`

```apex
public static GuardResult open(GuardPolicy policy, String payloadJson)
public static GuardResult rollback(GuardResult result)
public static GuardResult executeWithRollback(GuardPolicy policy, String payloadJson, GuardResultCallback businessLogic)
```

Opens Savepoint and enforces `MaxRecordsPerCall__c` ceiling. Returns `ALLOW` with savepoint attached, or `BLOCK` (gate: `ROLLBACK`).

**Interface:**

```apex
public interface GuardResultCallback {
  GuardResult execute(GuardResult allowResult);
}
```

---

## `AuditPublisher`

```apex
public static void publish(AuditContext ctx)
```

Publishes `AgentGuard_Audit__e` Platform Event. Never throws; failures logged at ERROR level.

### `AuditContext` (Fluent Builder)

```apex
new AuditPublisher.AuditContext()
    .withPolicyName(String)
    .withActionName(String)
    .withGateName(String)      // FACADE | SCHEMA | ACCESS | RATE | ROLLBACK
    .withDecision(String)      // ALLOW | BLOCK | THROTTLED | ROLLBACK
    .withReason(String)
    .withPayloadJson(String)   // Hashed to SHA-256, never stored verbatim
    .withLatencyMs(Long)
    .withFlagged(Boolean)
    .withActorId(String)       // Defaults to UserInfo.getUserId()
```

### Test Capture Mode

```apex
AuditPublisher.setCaptureMode(true);    // Enable capture
List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents(); // Get & clear
AuditPublisher.setCaptureMode(false);   // Disable
```

---

## `PolicyRegistry`

```apex
public static GuardPolicy resolve(String name)
public static void registerForTesting(GuardPolicy policy)
public static void clearForTesting()
```

Resolves effective policy for a name. Unknown names return `GuardPolicy.disabled(name)` (fail closed).

**Resolution order:**

1. Test override (`registerForTesting`)
2. In-memory metadata cache
3. SOQL query `Guard_Policy__mdt`
4. Disabled fallback
