# Getting Started

> **Status:** Full content available at v1.0. This page follows the blueprint's 5-minute quickstart contract.

## Prerequisites

- Salesforce CLI (`sf`) v2.x or later
- A Dev Hub org with 2GP packaging enabled
- Platform Cache partition named `AgentGuard` (see [Configuration Requirements](../CONFIG_REQUIREMENTS.md))
- Enterprise Edition, Developer Edition, or Scratch Org

## Quick Install (5 minutes)

### 1. Install the Package

```bash
sf package install --package AgentGuardSF@1.0.0-1 -o myScratchOrg
```

### 2. Deploy Example Policy

```bash
sf project deploy start -d examples/basic-invocable-wrap
```

### 3. Wrap Your First Action

```apex
@InvocableMethod(label='Update Account Territory')
public static List<Result> execute(List<Request> requests) {
    GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
    if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
    return TerritoryService.reassign(requests);
}
```

### 4. Watch Your First Blocked Call

```bash
sf agentguard audit tail   # Optional CLI plugin, ships at v0.8
```

## Detailed Walkthrough

### Step 1: Create Platform Cache Partition

Before installing, ensure your org has a Platform Cache partition named `AgentGuard`:

1. In Setup, search for **Platform Cache**
2. Click **New Platform Cache Partition**
3. Name: `AgentGuard`
4. Type: `Org Cache`
5. Session Cache: `0 MB` (not used)
6. Org Cache: `10 MB` (minimum recommended)
7. Default Partition: **No** (keep as non-default)

### Step 2: Deploy Guard Policy Metadata

The example includes a `Guard_Policy__mdt` record for `UpdateAccountTerritory`. Deploy it:

```bash
sf project deploy start -d examples/basic-invocable-wrap
```

This creates a policy with:

- **Schema Contract**: Requires `AccountId` (string), optional `Territory__c`
- **Max Records**: 5 per call
- **Rate Limit**: 10 calls/minute per user
- **Operation**: MODIFY (enforces update FLS)

### Step 3: Test the Integration

Open Anonymous Apex in Developer Console and run:

```apex
// This will be ALLOWED
List<TerritoryService.Request> reqs = new List<TerritoryService.Request>{
    new TerritoryService.Request('001...', 'West')
};
TerritoryService.execute(reqs);

// This will be BLOCKED (unknown field)
List<TerritoryService.Request> badReqs = new List<TerritoryService.Request>{
    new TerritoryService.Request('001...', 'West', 'HACKED__c')
};
try {
    TerritoryService.execute(badReqs);
} catch (AgentGuard.BlockedException e) {
    System.debug('BLOCKED: ' + e.getMessage());
}
```

### Step 4: Verify Audit Event

Check the Platform Event stream:

```apex
List<AgentGuard_Audit__e> events = [SELECT Decision__c, Reason__c, GateName__c
    FROM AgentGuard_Audit__e
    ORDER BY CreatedDate DESC LIMIT 5];
for (AgentGuard_Audit__e e : events) {
    System.debug(e.Decision__c + ' | ' + e.GateName__c + ' | ' + e.Reason__c);
}
```

You should see one `ALLOW | FACADE | ALLOWED_BY_POLICY` and one `BLOCK | SCHEMA | Unknown field: HACKED__c`.

## Troubleshooting

| Issue                              | Resolution                                                                 |
| ---------------------------------- | -------------------------------------------------------------------------- |
| `Cache partition not found`        | Create the `AgentGuard` Platform Cache partition in Setup                  |
| `Policy not found`                 | Ensure `Guard_Policy__mdt` record is deployed with correct `DeveloperName` |
| `Rate limit throttled immediately` | Check `RateLimitPerMinute__c` > 0 and `RateLimitWindowSeconds__c` >= 10    |
| `Savepoint rollback failed`        | Verify business logic doesn't use `Database.setSavepoint()` directly       |

## Next Steps

- Read [Policy Configuration](policy-configuration.md) to customize limits
- Review [Architecture](architecture.md) to understand the gate chain
- Check [Threat Model](threat-model.md) for what AgentGuard protects against
