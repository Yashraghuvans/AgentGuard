# agentforce-action-integration

> **Status:** Ships at v0.6+. Shows Agentforce actions wired through AgentGuard with declarative `Guard_Policy__mdt` policies — no Apex deployment needed to tune policies afterward.

## Contents

- `AgentforceCaseService.cls` — Two Agentforce actions: `createCase` and `updateCase`
- `AgentforceCreateCase.mdt-meta.xml` — Policy scoped to `Agentforce Service Agent` profile
- `AgentforceUpdateCase.mdt-meta.xml` — Policy scoped to `Agentforce Service Agent` profile

## Architecture

```
User → Agentforce Agent → @InvocableMethod (AgentforceCaseService)
                                      ↓
                              AgentGuard.wrap()
                                      ↓
                        SchemaValidator → AccessGate → RateLimiter → RollbackGuard
                                      ↓
                              Business Logic (DML)
                                      ↓
                              AuditPublisher → AgentGuard_Audit__e
```

The Agentforce agent calls the invocable method, which wraps execution with AgentGuard. The policy is scoped to the `Agentforce Service Agent` profile, so only that specific agent profile can invoke the action.

## Quick Deploy

```bash
# Create scratch org with Agentforce enabled
sf org create scratch -f config/project-scratch-def.json -a ag-agentforce

# Deploy AgentGuard source
sf project deploy start -o ag-agentforce

# Deploy Agentforce action example
sf project deploy start -d examples/agentforce-action-integration -o ag-agentforce
```

## Agentforce Setup

### 1. Register Actions in Agentforce

In Agentforce Agent Builder or via metadata:

1. Create a new **Action** of type **Apex**
2. Select `AgentforceCaseService.createCase` as the invocable method
3. Map inputs: `Subject` (required), `Description`, `Origin`, `Priority`, `AccountId`, `ContactId`
4. Save and activate

5. Create second action: `AgentforceCaseService.updateCase`
6. Map inputs: `Subject` (CaseId), `Description`, `Origin`, `Priority`

### 2. Configure Agent Profile

Ensure the Agentforce agent runs under a user with:

- Profile: `Agentforce Service Agent` (or one listed in `AllowedProfiles__c`)
- OR Permission Set: `Agentforce_Service_Agent` (or one listed in `AllowedPermissionSets__c`)

This is enforced by `AccessGate` via `Guard_Policy__mdt` scoping.

## Test It

### 1. Valid Create Case (ALLOW)

```apex
// As Agentforce Service Agent user
List<AgentforceCaseService.Request> reqs = new List<AgentforceCaseService.Request>{
    new AgentforceCaseService.Request('Login Issue')
};
reqs[0].Description = 'Cannot login after password reset';
reqs[0].Priority = 'High';
reqs[0].Origin = 'Agent';

AgentforceCaseService.createCase(reqs);

// Check audit
List<AgentGuard_Audit__e> events = [SELECT Decision__c, GateName__c, Reason__c
    FROM AgentGuard_Audit__e ORDER BY CreatedDate DESC LIMIT 1];
// Expected: ALLOW | FACADE | ALLOWED_BY_POLICY
```

### 2. Prompt Injection Attempt — Bulk Payload (BLOCK at SCHEMA)

```apex
// Attacker tries to inject bulk payload via prompt injection
// Policy only allows single record (MaxRecordsPerCall__c = 1)
List<AgentforceCaseService.Request> bulkReqs = new List<AgentforceCaseService.Request>();
for (Integer i = 0; i < 10; i++) {
    bulkReqs.add(new AgentforceCaseService.Request('Auto Case ' + i));
}

try {
    AgentforceCaseService.createCase(bulkReqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
    System.debug('Gate: ' + e.gateName);
}
// Expected: BLOCKED: Record count 10 exceeds policy ceiling of 1 | Gate: ROLLBACK
// OR if schema catches it first: Unknown field or structure
```

### 3. Schema Violation — Unknown Field (BLOCK at SCHEMA)

```apex
// Malformed payload with injected field
List<AgentforceCaseService.Request> badReqs = new List<AgentforceCaseService.Request>{
    new AgentforceCaseService.Request('Test')
};
// Manually serialize with injected field
String badPayload = '[{"Subject":"Test","InjectedField__c":"Malicious"}]';

try {
    GuardResult check = AgentGuard.wrap('AgentforceCreateCase', badPayload);
    if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED at SCHEMA: ' + e.getMessage());
}
// Expected: BLOCKED: Unknown field: InjectedField__c
```

### 4. Rate Limit Test (THROTTLED at RATE)

```apex
// Policy allows 20/minute
for (Integer i = 0; i < 22; i++) {
    List<AgentforceCaseService.Request> reqs = new List<AgentforceCaseService.Request>{
        new AgentforceCaseService.Request('Rate Test ' + i)
    };
    try {
        AgentforceCaseService.createCase(reqs);
    } catch (AgentGuard.BlockedException e) {
        if (e.decision == 'THROTTLED') {
            System.debug('THROTTLED on call ' + (i+1));
        }
    }
}
// Expected: First 20 succeed, 21st+ THROTTLED
```

### 5. Unauthorized Profile (BLOCK at ACCESS)

Log in as a user with `Standard User` profile (not in allowed list):

```apex
List<AgentforceCaseService.Request> reqs = new List<AgentforceCaseService.Request>{
    new AgentforceCaseService.Request('Unauthorized Test')
};

try {
    AgentforceCaseService.createCase(reqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED at ACCESS: ' + e.getMessage());
}
// Expected: BLOCKED: Profile not authorized
```

### 6. Priority Enum Validation

```apex
List<AgentforceCaseService.Request> reqs = new List<AgentforceCaseService.Request>{
    new AgentforceCaseService.Request('Test')
};
reqs[0].Priority = 'InvalidPriority';

try {
    AgentforceCaseService.createCase(reqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
}
// Expected: BLOCKED at SCHEMA: Field Priority value not in allowed enum
```

## Policy Configuration Explained

Both policies have:

| Field                      | Value                                           | Purpose                                          |
| -------------------------- | ----------------------------------------------- | ------------------------------------------------ |
| `IsActive__c`              | `true`                                          | Enabled                                          |
| `TargetSObjectType__c`     | `Case`                                          | Action targets Case                              |
| `Operation__c`             | `CREATE` / `MODIFY`                             | Enforces create/update CRUD/FLS                  |
| `MaxRecordsPerCall__c`     | `1`                                             | Single record per call (prevents bulk injection) |
| `RateLimitPerMinute__c`    | `20`                                            | Reasonable for agent traffic                     |
| `AllowedProfiles__c`       | `Agentforce Service Agent;System Administrator` | Only agent profile + admin                       |
| `AllowedPermissionSets__c` | `Agent_Tools;Agentforce_Service_Agent`          | Agent-specific permsets                          |

**Create Schema Contract:**

```json
{
  "properties": {
    "Subject": { "type": "string", "required": true },
    "Description": { "type": "string", "nullable": true },
    "Origin": { "type": "string", "nullable": true },
    "Priority": { "type": "string", "enum": ["Low", "Medium", "High", "Critical"], "nullable": true },
    "AccountId": { "type": "string", "nullable": true },
    "ContactId": { "type": "string", "nullable": true }
  },
  "required": ["Subject"]
}
```

**Update Schema Contract:**

```json
{
  "properties": {
    "Subject": { "type": "string", "required": true }, // Used as CaseId
    "Description": { "type": "string", "nullable": true },
    "Origin": { "type": "string", "nullable": true },
    "Priority": { "type": "string", "enum": ["Low", "Medium", "High", "Critical"], "nullable": true }
  },
  "required": ["Subject"]
}
```

## Key Security Features Demonstrated

1. **Profile Scoping** — Only `Agentforce Service Agent` profile can invoke
2. **Single-Record Enforcement** — `MaxRecordsPerCall__c = 1` prevents bulk injection attacks
3. **Schema Contract** — Rejects unknown fields (prompt injection defense)
4. **Enum Validation** — `Priority` must be one of allowed values
5. **Rate Limiting** — 20 calls/minute prevents abuse
6. **Audit Trail** — Every decision logged to `AgentGuard_Audit__e`

## Audit Event Verification

```apex
List<AgentGuard_Audit__e> events = [SELECT Decision__c, GateName__c, Reason__c,
    PolicyName__c, ActorId__c, Flagged__c, LatencyMs__c
    FROM AgentGuard_Audit__e
    ORDER BY CreatedDate DESC LIMIT 10];

for (AgentGuard_Audit__e e : events) {
    System.debug(e.Decision__c + ' | ' + e.GateName__c + ' | ' + e.PolicyName__c +
        ' | ' + e.Reason__c + ' | ' + e.LatencyMs__c + 'ms | Flagged: ' + e.Flagged__c);
}
```

## Cleanup

```bash
sf org delete scratch -o ag-agentforce -p
```

## Production Considerations

1. **Enable Platform Cache partition `AgentGuard`** in production org
2. **Create `Agentforce Service Agent` profile** if not present (Agentforce provisioning)
3. **Assign `Agentforce_Service_Agent` permission set** to agent user
4. **Monitor audit events** via LWC dashboard or CLI plugin
5. **Adjust rate limits** based on actual agent traffic patterns
