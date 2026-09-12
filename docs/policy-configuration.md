# Policy Configuration (`Guard_Policy__mdt`)

> **Status:** Complete at v1.0. RULES.md #13: any PR adding a policy field updates this page in the same PR.

## Posture

**Restrictive by default.** Every field defaults to its most restrictive safe value; nothing is permitted unless explicitly configured.

| Default Value                      | Behavior                                                 |
| ---------------------------------- | -------------------------------------------------------- |
| `IsActive__c = false`              | Policy is disabled — every call blocked at AccessGate    |
| `MaxRecordsPerCall__c = 0`         | Zero ceiling — every call blocked at RollbackGuard       |
| `RateLimitPerMinute__c = 0`        | Zero budget — every call throttled at RateLimiter        |
| `SchemaContract__c = empty`        | No contract — every call blocked at SchemaValidator      |
| `AllowedProfiles__c = empty`       | No extra profile restriction (but policy must be active) |
| `AllowedPermissionSets__c = empty` | No extra permset restriction                             |

## Field Reference

| Field                       | Type                   | Default | Purpose                                                                                                                   |
| --------------------------- | ---------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| `DeveloperName`             | Text (unique)          | —       | Policy identifier; matches `policyName` in `AgentGuard.wrap()`                                                            |
| `Label`                     | Text                   | —       | Human-readable name for UI                                                                                                |
| `IsActive__c`               | Checkbox               | `false` | Master kill-switch. `false` blocks all calls to this policy.                                                              |
| `TargetSObjectType__c`      | Text (80)              | empty   | API name of the sObject the action mutates or reads (e.g., `Account`, `Custom_Object__c`).                                |
| `Operation__c`              | Picklist               | `READ`  | Data operation type: `READ`, `CREATE`, `MODIFY`, `REMOVE`. Determines which CRUD/FLS checks AccessGate enforces.          |
| `SchemaContract__c`         | Long Text Area (32768) | empty   | JSON schema contract defining allowed payload keys, types, required fields. Consumed by SchemaValidator.                  |
| `MaxRecordsPerCall__c`      | Number (18,0)          | `0`     | Maximum records allowed per call. `0` blocks every call.                                                                  |
| `RateLimitPerMinute__c`     | Number (18,0)          | `0`     | Maximum invocations per rolling window per user per action. `0` throttles every call.                                     |
| `RateLimitWindowSeconds__c` | Number (18,0)          | `60`    | Rolling window length in seconds. Clamped to `[10, 3600]`.                                                                |
| `AllowedProfiles__c`        | Long Text Area (32768) | empty   | Semicolon-separated list of Profile Names allowed to invoke. Empty = no extra profile restriction.                        |
| `AllowedPermissionSets__c`  | Long Text Area (32768) | empty   | Semicolon-separated list of Permission Set Names (DeveloperName) allowed to invoke. Empty = no extra permset restriction. |

## Schema Contract Format

The `SchemaContract__c` field accepts a JSON object with this structure:

```json
{
  "properties": {
    "FieldName__c": {
      "type": "string|integer|number|boolean|array|object",
      "required": true|false,
      "nullable": true|false,
      "minimum": 0,
      "maximum": 100,
      "enum": ["Value1", "Value2"]
    }
  },
  "required": ["FieldName__c"]
}
```

### Supported Types

| JSON Type | Apex Validation                                                             |
| --------- | --------------------------------------------------------------------------- |
| `string`  | `instanceof String`; supports `enum` and `nullable`                         |
| `integer` | `instanceof Integer`; supports `minimum`, `maximum`, `nullable`             |
| `number`  | `instanceof Double/Integer/Long`; supports `minimum`, `maximum`, `nullable` |
| `boolean` | `instanceof Boolean`; supports `nullable`                                   |
| `array`   | `instanceof List<Object>`; supports `nullable`                              |
| `object`  | `instanceof Map<String, Object>`; supports `nullable`                       |

### Example Contracts

**Single-record territory update:**

```json
{
  "properties": {
    "AccountId": { "type": "string", "required": true },
    "Territory__c": { "type": "string", "nullable": true }
  },
  "required": ["AccountId"]
}
```

**Bulk operation with numeric validation:**

```json
{
  "properties": {
    "records": {
      "type": "array",
      "required": true,
      "items": {
        "type": "object",
        "properties": {
          "Id": { "type": "string", "required": true },
          "Quantity__c": { "type": "integer", "minimum": 1, "maximum": 1000 }
        }
      }
    }
  },
  "required": ["records"]
}
```

## Creating Policies

### Via Metadata Deploy (Recommended)

```xml
<!-- objects/Guard_Policy__mdt/UpdateAccountTerritory.mdt-meta.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>Update Account Territory</label>
    <protected>false</protected>
    <values>
        <field>IsActive__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>TargetSObjectType__c</field>
        <value xsi:type="xsd:string">Account</value>
    </values>
    <values>
        <field>Operation__c</field>
        <value xsi:type="xsd:string">MODIFY</value>
    </values>
    <values>
        <field>SchemaContract__c</field>
        <value xsi:type="xsd:string">{...JSON contract...}</value>
    </values>
    <values>
        <field>MaxRecordsPerCall__c</field>
        <value xsi:type="xsd:double">5.0</value>
    </values>
    <values>
        <field>RateLimitPerMinute__c</field>
        <value xsi:type="xsd:double">10.0</value>
    </values>
    <values>
        <field>RateLimitWindowSeconds__c</field>
        <value xsi:type="xsd:double">60.0</value>
    </values>
    <values>
        <field>AllowedProfiles__c</field>
        <value xsi:type="xsd:string">Agentforce Service Agent;System Administrator</value>
    </values>
    <values>
        <field>AllowedPermissionSets__c</field>
        <value xsi:type="xsd:string">Agent_Tools;Integration_User</value>
    </values>
</CustomMetadata>
```

### Via Anonymous Apex (Testing Only)

```apex
Guard_Policy__mdt p = new Guard_Policy__mdt(
    DeveloperName = 'TestAction',
    Label = 'Test Action',
    IsActive__c = true,
    TargetSObjectType__c = 'Account',
    Operation__c = 'MODIFY',
    SchemaContract__c = '{"properties": {"AccountId": {"type": "string", "required": true}}, "required": ["AccountId"]}',
    MaxRecordsPerCall__c = 10,
    RateLimitPerMinute__c = 100,
    RateLimitWindowSeconds__c = 60
);
insert p;
```

## Policy Resolution Order

1. **Test override** (`PolicyRegistry.registerForTesting()`) — highest precedence, for unit tests only
2. **In-memory metadata cache** — populated on first successful SOQL query per transaction
3. **SOQL query** — `SELECT ... FROM Guard_Policy__mdt WHERE DeveloperName = :name`
4. **Disabled fallback** — `GuardPolicy.disabled(name)` (all knobs zero/false) — fail closed

## Best Practices

1. **Always deploy policies via CI** — never edit directly in production (Custom Metadata Types enforce this)
2. **Start restrictive, relax incrementally** — enable `IsActive__c` last, after schema and limits are verified
3. **Use profile/permset scoping** — limit which agents/users can invoke sensitive actions
4. **Set realistic rate limits** — too low causes false throttles; too high defeats the gate
5. **Document schema contracts** — treat them as API contracts; version them with your action code
