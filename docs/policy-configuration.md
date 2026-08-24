# Policy Configuration (`Guard_Policy__mdt`)

> **Status:** drafted — field reference is finalized at v0.6 when the metadata
> type ships. RULES.md #13: any PR adding a policy field updates this page in the
> same PR.

## Posture

Restrictive by default. Every field defaults to its most restrictive safe value;
nothing is permitted unless explicitly configured.

## Planned Field Reference

| Field | Type | Default | Purpose |
| --- | --- | --- | --- |
| `ActionName__c` | Text (unique) | — | Invocable action this policy governs |
| `SchemaContract__c` | Long Text Area | empty = BLOCK | Declared payload contract (field names, types, required-ness, ranges) |
| `MaxRecordsPerCall__c` | Number | 0 = BLOCK | RollbackGuard record ceiling |
| `RateLimitPerMinute__c` | Number | 0 = BLOCK | Sliding-window budget per agent per action |
| `AllowedProfiles__c` | Text | empty = none allowed | Profile scoping |
| `AllowedPermissionSets__c` | Text | empty = none allowed | Permission-set scoping |
| `Enabled__c` | Checkbox | false | Kill switch per action |

## Examples

Worked examples per action type ship at v0.6 alongside the example projects in
`examples/`.
