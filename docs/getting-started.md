# Getting Started

This is the code-heavy companion to the [README](../README.md): every command and code sample needed to deploy AgentGuard, wrap your first action, and watch it enforce — in one place.

## Prerequisites

| Requirement                  | Notes                                                              |
| ---------------------------- | ------------------------------------------------------------------ |
| Salesforce DX CLI (`sf`) v2+ | `npm install -g @salesforce/cli`                                   |
| Dev Hub org                  | Enterprise, Performance, or Unlimited Edition with Dev Hub enabled |
| API version 62.0+            | Set in `sfdx-project.json`                                         |

## 1. Deploy

### Option A — from source (recommended for trying it out)

```bash
# Authenticate to your Dev Hub
sf org login web --set-default-dev-hub --alias devhub

# Create a scratch org
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias agentguard-dev --duration-days 30 --set-default

# Deploy all metadata
sf project deploy start --target-org agentguard-dev

# Run the full test suite (117 tests, should all pass)
sf apex run test --target-org agentguard-dev --code-coverage --result-format human --wait 30
```

### Option B — install the beta package

```bash
sf package install --package 04tfj000000XcL3AAK --target-org myOrgAlias --wait 10
```

Or via browser install link — production/Dev org: [login.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000XcL3AAK](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000XcL3AAK) · sandbox: [test.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000XcL3AAK](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfj000000XcL3AAK)

| Field              | Value                                                                                                      |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| Version            | `0.8.0.1`                                                                                                  |
| Package Id         | `0Hofj0000004KhhCAE` (alias `AgentGuardSF`)                                                                |
| Subscriber Version | `04tfj000000XcL3AAK`                                                                                       |
| Code coverage      | 83% (passed coverage check)                                                                                |
| Released           | No — beta, unlocked package. Installs fine in sandboxes/scratch/dev orgs; not yet promoted for production. |

## 2. Create the Platform Cache partition (required for rate limiting)

1. Go to **Setup > Platform Cache**
2. Click **New Platform Cache Partition**
3. Set the name to **`AgentGuard`**
4. Allocate at least 1 MB of org cache
5. Save

Without this partition, `RateLimiter` operates in fail-open mode: it logs a flagged audit event but allows the call, rather than blocking every agent action because a cache dependency is unavailable.

## 3. Wrap your first action

Wrapping an existing `@InvocableMethod` requires one check before your business logic runs:

```apex
@InvocableMethod(label='Update Account Territory')
public static List<Result> execute(List<Request> requests) {

    GuardResult check = AgentGuard.wrap(
        'UpdateAccountTerritory',   // matches Guard_Policy__mdt DeveloperName
        JSON.serialize(requests)    // raw AI-originated payload
    );

    if (!check.isAllowed) {
        throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
    }

    // Existing logic runs unchanged — validated, access-checked,
    // throttled, inside a Savepoint boundary, and audited.
    return TerritoryService.reassign(requests);
}
```

For automatic rollback when business logic throws, use `wrapAndExecute` instead of a manual `wrap` + `throw`:

```apex
GuardResult result = AgentGuard.wrapAndExecute(
    'UpdateAccountTerritory',
    JSON.serialize(requests),
    new MyCallback()
);

private class MyCallback implements RollbackGuard.GuardResultCallback {
    public GuardResult execute(GuardResult allow) {
        // your DML here — rolled back automatically if this throws
        return TerritoryService.reassign(requests);
    }
}
```

The policy referenced by name (`UpdateAccountTerritory` above) must exist as a `Guard_Policy__mdt` record — see [Policy Configuration](policy-configuration.md) for the full field reference and schema contract format. The worked example in `examples/basic-invocable-wrap` ships a ready-made one.

## 4. Try a blocked call

Deploy the worked example, then run this in Developer Console → Execute Anonymous:

```apex
List<Account> accs = [SELECT Id FROM Account LIMIT 1];

// Allowed — matches the schema contract
TerritoryService.execute(new List<TerritoryService.Request>{
    new TerritoryService.Request(accs[0].Id, 'West')
});

// Blocked — an out-of-contract field, the shape a real prompt-injection
// payload would take. TerritoryService.Request is strongly typed, so this
// has to go through the facade directly with raw JSON to demonstrate it.
GuardResult check = AgentGuard.wrap(
    'UpdateAccountTerritory',
    '[{"AccountId":"' + accs[0].Id + '","Territory":"West","HACKED__c":"pwn"}]'
);
System.debug('BLOCKED: ' + check.reason + ' | gate=' + check.gateName);
```

Expect `BLOCKED: Unknown field: HACKED__c | gate=SCHEMA`.

## 5. Watch the audit trail

Platform Events aren't queryable via SOQL, so pick one of these instead of `[SELECT ... FROM AgentGuard_Audit__e]` (that query doesn't compile):

- **Dashboard:** drag the `guardAuditDashboard` Lightning component onto any page — see [Architecture](architecture.md) for how it subscribes.
- **Terminal:** install the CLI plugin and tail the stream live:

  ```bash
  # Not yet published to npm — build and link it locally:
  cd plugins/sf-agentguard && npm install && npm run build && cd ../..
  sf plugins link plugins/sf-agentguard

  sf agentguard audit tail --target-org agentguard-dev
  ```

  Full command reference: [plugins/sf-agentguard/README.md](../plugins/sf-agentguard/README.md).

You should see one `ALLOW | FACADE | ALLOWED_BY_POLICY` and one `BLOCK | SCHEMA | Unknown field: HACKED__c`.

## Troubleshooting

| Issue                              | Resolution                                                                 |
| ---------------------------------- | -------------------------------------------------------------------------- |
| `Cache partition not found`        | Create the `AgentGuard` Platform Cache partition in Setup                  |
| `Policy not found`                 | Ensure `Guard_Policy__mdt` record is deployed with correct `DeveloperName` |
| `Rate limit throttled immediately` | Check `RateLimitPerMinute__c` > 0 and `RateLimitWindowSeconds__c` >= 10    |
| `Savepoint rollback failed`        | Verify business logic doesn't use `Database.setSavepoint()` directly       |

## Next Steps

- [Policy Configuration](policy-configuration.md) — customize schema contracts, limits, and scoping
- [Architecture](architecture.md) — the gate chain, request lifecycle, ADRs
- [Threat Model](threat-model.md) — what AgentGuard protects against, and what it doesn't
