# FAQ

> **Status:** Complete at v1.0. Grows with real user questions.

## General

### How is this different from the Einstein / Agentforce Trust Layer?

The Trust Layer protects what the LLM **sees** (data masking, grounding, retention at the prompt boundary). AgentGuard SF is the gate that decides, in real time, whether an agent-issued Apex action is allowed to touch your data **at all**. They are complementary — see [LIMITS.md](/context/LIMITS.md).

**One-line answer:** "The Trust Layer protects what the LLM sees; Command Center reports what agents did; AgentGuard SF is the gate that decides, in real time, whether an agent-issued Apex action is allowed to touch your data at all."

### Is this a replacement for Agentforce Command Center?

No. Command Center reports what agents did, after the fact. AgentGuard enforces **before execution**. AgentGuard's audit events can feed into or alongside Command Center.

### Does it work with non-Agentforce agents (MCP servers, custom LLMs)?

Yes — it is framework-agnostic. Anything that can call your `@InvocableMethod` goes through the same gates. The facade `AgentGuard.wrap()` doesn't know or care who the caller is.

### What happens if AgentGuard itself has a bug?

It **fails closed**: an internal exception becomes a BLOCK, never an ALLOW (ADR-002). Availability degrades before security does — deliberately.

### What does a wrapped call cost in governor limits?

| Resource        | Overhead per `AgentGuard.wrap()`                       |
| --------------- | ------------------------------------------------------ |
| SOQL Queries    | 1–2 (policy lookup + optional FLS describe cache miss) |
| DML Statements  | 0 in the gate path itself (only Savepoint)             |
| CPU Time        | Typically 2–6 ms                                       |
| Heap Size       | <10 KB                                                 |
| Platform Cache  | 1 read + 1 write (rate limiter)                        |
| Platform Events | 1 publish (async)                                      |

For a bulk Invocable call handling 200 records, overhead stays effectively flat — one policy lookup and one rate-limit check per action.

### Why Custom Metadata Types instead of Custom Settings for policies?

Policy changes should ride the same review/CI pipeline as code. A Custom Setting edited directly in production would bypass that entirely (ADR-003).

## Implementation

### Can I use only one gate (e.g., just AccessGate)?

Use the per-gate toggles on `Guard_Policy__mdt` rather than integrating gates individually:

- Set `RateLimitPerMinute__c = 0` to disable rate limiting
- Set `MaxRecordsPerCall__c = 0` to disable rollback guard
- Leave `SchemaContract__c` empty to disable schema validation (not recommended)

The facade `AgentGuard.wrap()` always runs the full chain; gates that aren't configured simply return their restrictive default (BLOCK/THROTTLE).

### How do I test my wrapped action?

1. Use `PolicyRegistry.registerForTesting()` in `@TestSetup` to inject a test policy
2. Call `AgentGuard.wrap()` directly in test methods
3. Use `AuditPublisher.setCaptureMode(true)` to capture audit events for assertions
4. Use `System.runAs()` with restricted users to verify AccessGate behavior

See `AgentGuardTest.cls` and `TerritoryReassignFlowTest.cls` for patterns.

### Can I wrap a Flow or Process Builder action?

Yes — any `@InvocableMethod` can be wrapped. The payload JSON passed to `wrap()` should match what the invocable receives.

### What if my payload is a custom Apex type, not a Map?

`AgentGuard.wrap()` expects a JSON string. Serialize your request object:

```apex
String payload = JSON.serialize(requests); // List<YourRequestClass>
GuardResult check = AgentGuard.wrap('YourAction', payload);
```

Schema validation works on the deserialized JSON structure.

### How do I handle the BlockedException?

```apex
try {
    GuardResult check = AgentGuard.wrap('ActionName', JSON.serialize(requests));
    if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
    return BusinessLogic.execute(requests);
} catch (AgentGuard.BlockedException e) {
    // e.decision = BLOCK | THROTTLED | ROLLBACK
    // e.gateName = SCHEMA | ACCESS | RATE | ROLLBACK | FACADE
    // Log, return error response, etc.
    throw new AuraHandledException('Action blocked: ' + e.getMessage());
}
```

## Configuration

### My policy isn't being picked up — why?

1. Verify `Guard_Policy__mdt` record exists with correct `DeveloperName`
2. Check `IsActive__c = true`
3. Ensure policy is deployed to the same org
4. In tests: use `PolicyRegistry.registerForTesting()` — metadata isn't queried in test context unless explicitly deployed

### Rate limiter isn't throttling — what's wrong?

1. Check `RateLimitPerMinute__c > 0` on the policy
2. Verify Platform Cache partition `AgentGuard` exists and has capacity
3. In tests: call `RateLimiter.clearCache('ActionName')` between test runs
4. Check audit events for `Flagged__c = true` (cache outage fallback)

### AccessGate blocking valid users — how to debug?

1. Check `AllowedProfiles__c` and `AllowedPermissionSets__c` on policy
2. Verify running user's Profile Name matches exactly (case-sensitive)
3. Verify Permission Set assignment: `PermissionSetAssignment` records exist
4. For field-level blocks: check `Security.stripInaccessible()` behavior — it strips, doesn't throw

## Operations

### How do I view audit events in production?

**Option 1: SOQL (via Platform Event subscriber)**

```apex
// Subscribe via trigger or Apex to persist to custom object for querying
```

**Option 2: CLI Plugin (v0.8+)**

```bash
sf agentguard audit tail
sf agentguard audit summary --hours 24
```

**Option 3: LWC Dashboard (optional)**
Deploy `guardAuditDashboard` component to a Lightning page.

### Can I query audit events via SOQL directly?

Platform Events are not natively queryable via standard SOQL history. You must:

- Subscribe via Apex trigger and persist to a custom object, OR
- Use the Event Monitoring / Change Data Capture stream, OR
- Use the optional LWC dashboard which uses `empApi` to stream events

### How do I rotate audit event retention?

Platform Events (High Volume) have a 72-hour retention by default. For longer retention, subscribe and persist to a custom object with your own retention policy.

## Security & Compliance

### Does AgentGuard make my org SOC 2 / HIPAA / GDPR compliant?

**No.** AgentGuard provides **technical controls that contribute evidence** toward these frameworks (see [Compliance Mapping](compliance.md)), but does not by itself make an org compliant. Compliance requires organizational processes, policies, and additional controls.

### Is AgentGuard certified?

No. It is an open-source security utility library under MIT license. There is no formal certification.

### Can I use this in a managed package?

Yes — it's an unlocked 2GP package. You can depend on it or include the source directly. The MIT license permits commercial use.

## Troubleshooting

| Symptom                     | Likely Cause                                   | Fix                                                               |
| --------------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| All calls BLOCK             | Policy `IsActive__c = false`                   | Enable policy                                                     |
| All calls THROTTLE          | `RateLimitPerMinute__c = 0`                    | Set budget > 0                                                    |
| All calls BLOCK at SCHEMA   | `SchemaContract__c` empty or invalid           | Add valid JSON schema                                             |
| BLOCK at ACCESS for admin   | Profile/Permission set scoping too restrictive | Check `AllowedProfiles__c` / `AllowedPermissionSets__c`           |
| "Cache partition not found" | `AgentGuard` Platform Cache partition missing  | Create in Setup → Platform Cache                                  |
| Test fails with "no policy" | Metadata not deployed in test                  | Use `PolicyRegistry.registerForTesting()`                         |
| Rollback not working        | Savepoint not attached                         | Use `AgentGuard.wrapAndExecute()` or call `AgentGuard.rollback()` |
| Audit events not appearing  | `EventBus.publish` async                       | Query after `Test.stopTest()` in tests; allow ~seconds in prod    |
