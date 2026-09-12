# basic-invocable-wrap

> **Status:** Ships at v0.1. Copy-paste starting point for wrapping an existing `@InvocableMethod` with `AgentGuard.wrap()`.

## Contents

- `TerritoryService.cls` — Sample invocable action for updating Account territories
- `UpdateAccountTerritory.mdt-meta.xml` — Matching restrictive `Guard_Policy__mdt` policy record

## Quick Deploy (5 minutes)

### Prerequisites

1. Scratch org with Platform Cache partition `AgentGuard` (see [Configuration Requirements](../../CONFIG_REQUIREMENTS.md))
2. AgentGuard package installed or source deployed

### Deploy

```bash
# Create scratch org
sf org create scratch -f config/project-scratch-def.json -a ag-demo

# Deploy AgentGuard source (if not installed as package)
sf project deploy start -o ag-demo

# Deploy example
sf project deploy start -d examples/basic-invocable-wrap -o ag-demo
```

## Test It

### 1. Valid Call (ALLOW)

Open Anonymous Apex in Developer Console:

```apex
// Create test account
Account acc = new Account(Name = 'Test Territory Account');
insert acc;

// Valid payload: AccountId + Territory__c
List<TerritoryService.Request> reqs = new List<TerritoryService.Request>{
    new TerritoryService.Request(acc.Id, 'West')
};

TerritoryService.execute(reqs);

// Verify
Account updated = [SELECT Territory__c FROM Account WHERE Id = :acc.Id];
System.assertEquals('West', updated.Territory__c, 'Territory should be updated');

// Check audit event
List<AgentGuard_Audit__e> events = [SELECT Decision__c, GateName__c, Reason__c
    FROM AgentGuard_Audit__e
    ORDER BY CreatedDate DESC LIMIT 1];
System.debug('Audit: ' + events[0].Decision__c + ' | ' + events[0].GateName__c + ' | ' + events[0].Reason__c);
// Expected: ALLOW | FACADE | ALLOWED_BY_POLICY
```

### 2. Invalid Schema (BLOCK at SCHEMA gate)

```apex
// Invalid payload: unknown field
List<TerritoryService.Request> badReqs = new List<TerritoryService.Request>{
    new TerritoryService.Request(acc.Id, 'West', 'HACKED__c')
};

try {
    TerritoryService.execute(badReqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
    System.debug('Decision: ' + e.decision);
    System.debug('Gate: ' + e.gateName);
}
// Expected: BLOCKED: Unknown field: HACKED__c | Decision: BLOCK | Gate: SCHEMA
```

### 3. Missing Required Field (BLOCK at SCHEMA gate)

```apex
// Invalid payload: missing required AccountId
List<TerritoryService.Request> badReqs = new List<TerritoryService.Request>{
    new TerritoryService.Request()  // AccountId is null
};

try {
    TerritoryService.execute(badReqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
}
// Expected: BLOCKED: Missing required field: AccountId
```

### 4. Exceeds Record Limit (BLOCK at ROLLBACK gate)

```apex
// Create 6 accounts (policy allows max 5)
List<Account> accounts = new List<Account>();
for (Integer i = 0; i < 6; i++) {
    accounts.add(new Account(Name = 'Bulk Test ' + i));
}
insert accounts;

List<TerritoryService.Request> bulkReqs = new List<TerritoryService.Request>();
for (Account a : accounts) {
    bulkReqs.add(new TerritoryService.Request(a.Id, 'East'));
}

try {
    TerritoryService.execute(bulkReqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
}
// Expected: BLOCKED: Record count 6 exceeds policy ceiling of 5
```

### 5. Rate Limit Exceeded (THROTTLED at RATE gate)

```apex
// Call 11 times (policy allows 10/minute)
for (Integer i = 0; i < 11; i++) {
    List<TerritoryService.Request> reqs = new List<TerritoryService.Request>{
        new TerritoryService.Request(acc.Id, 'North')
    };
    try {
        TerritoryService.execute(reqs);
    } catch (AgentGuard.BlockedException e) {
        if (e.decision == 'THROTTLED') {
            System.debug('THROTTLED on call ' + (i+1) + ': ' + e.getMessage());
        }
    }
}
// Expected: First 10 succeed, 11th THROTTLED
```

### 6. Access Denied (BLOCK at ACCESS gate)

Log in as a user with 'Read Only' profile (or assign restricted profile), then:

```apex
// Same valid payload, but restricted user
List<TerritoryService.Request> reqs = new List<TerritoryService.Request>{
    new TerritoryService.Request(acc.Id, 'South')
};

try {
    TerritoryService.execute(reqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
}
// Expected: BLOCKED: Object not updateable or Profile not authorized
```

## Policy Configuration Explained

The deployed `Guard_Policy__mdt` record (`UpdateAccountTerritory`) has:

| Field                       | Value                                           | Purpose                                                  |
| --------------------------- | ----------------------------------------------- | -------------------------------------------------------- |
| `IsActive__c`               | `true`                                          | Policy enabled                                           |
| `TargetSObjectType__c`      | `Account`                                       | Action mutates Account                                   |
| `Operation__c`              | `MODIFY`                                        | Enforces update CRUD/FLS                                 |
| `SchemaContract__c`         | JSON (see below)                                | Requires `AccountId`, allows `Territory__c`, `Status__c` |
| `MaxRecordsPerCall__c`      | `5`                                             | Max 5 accounts per call                                  |
| `RateLimitPerMinute__c`     | `10`                                            | 10 calls/minute per user                                 |
| `RateLimitWindowSeconds__c` | `60`                                            | Rolling 60-second window                                 |
| `AllowedProfiles__c`        | `Agentforce Service Agent;System Administrator` | Only these profiles                                      |
| `AllowedPermissionSets__c`  | `Agent_Tools;Integration_User`                  | Or these permsets                                        |

**Schema Contract:**

```json
{
  "properties": {
    "AccountId": { "type": "string", "required": true },
    "Territory__c": { "type": "string", "nullable": true },
    "Status__c": { "type": "string", "nullable": true }
  },
  "required": ["AccountId"]
}
```

## Audit Event Verification

After running tests, query the audit stream:

```apex
List<AgentGuard_Audit__e> events = [SELECT Decision__c, GateName__c, Reason__c,
    PayloadHash__c, LatencyMs__c, Flagged__c
    FROM AgentGuard_Audit__e
    ORDER BY CreatedDate DESC LIMIT 10];

for (AgentGuard_Audit__e e : events) {
    System.debug(e.Decision__c + ' | ' + e.GateName__c + ' | ' + e.Reason__c +
        ' | ' + e.LatencyMs__c + 'ms | Flagged: ' + e.Flagged__c);
}
```

You should see one event per call with the decision, gate name, and reason.

## Cleanup

```bash
sf org delete scratch -o ag-demo -p
```

## Next Steps

1. Copy `TerritoryService.cls` pattern to your own invocable actions
2. Create `Guard_Policy__mdt` records for each action
3. Adjust schema contract, rate limits, and record ceilings per action
4. Review [Policy Configuration](../../docs/policy-configuration.md) for all options
