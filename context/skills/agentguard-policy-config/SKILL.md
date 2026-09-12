---
name: agentguard-policy-config
description: Create or tune a Guard_Policy__mdt record that configures how AgentGuard SF governs one action — schema contract, CRUD/FLS target, rate limit, max-records ceiling, and profile/permission-set scoping. Use when a user says "configure a policy", "set a rate limit", "limit records per call", "restrict which profiles can call this", or asks how AgentGuard decides ALLOW vs BLOCK for an action.
---

# Configure a Guard_Policy__mdt policy

## Goal

Define, per action, exactly what a permitted call looks like. Everything is
restrictive-by-default: unset/blank never means "allow anything permissive".

## The fields

| Field                       | Meaning                                                            | Restrictive default guidance                                 |
| --------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------ |
| `IsActive__c`               | Whether this policy is enforced                                    | Start `true`; a deployed-but-inactive policy fails closed    |
| `SchemaContract__c`         | Declared payload shape (field names, types, required-ness, ranges) | List every allowed key; unknown top-level keys are rejected  |
| `TargetSObjectType__c`      | SObject the action mutates                                         | Set the exact API name (e.g. `Account`)                      |
| `Operation__c`              | CRUD op being gated (e.g. READ/CREATE/UPDATE/DELETE)               | Set the minimum the action needs                             |
| `MaxRecordsPerCall__c`      | Rollback ceiling — calls affecting more roll back                  | Set to the real single-call max, not a generous round number |
| `RateLimitPerMinute__c`     | Allowed calls per window per agent/action                          | Set to expected legitimate volume + small margin             |
| `RateLimitWindowSeconds__c` | Sliding-window size                                                | Default 60; shorten for burst-sensitive actions              |
| `AllowedProfiles__c`        | Profiles permitted to invoke (scoping)                             | List explicitly; blank = no profile passes                   |
| `AllowedPermissionSets__c`  | Permission sets permitted to invoke                                | List explicitly                                              |

## Steps

1. **Name the policy** with the same DeveloperName the `AgentGuard.wrap('<name>', ...)`
   call passes. They must match exactly.

2. **Author the metadata record** under
   `force-app/main/default/objects/Guard_Policy__mdt/` as
   `<PolicyName>.md-meta.xml`. Copy an existing example from
   `examples/basic-invocable-wrap/.../Guard_Policy__mdt/UpdateAccountTerritory.md-meta.xml`.

3. **Write the schema contract** to match the action's real request shape — single
   record vs list, required fields, allowed picklist values. This is the primary
   defense against a prompt-injected bulk/out-of-contract mutation.

4. **Set the ceiling and rate limit** to the _legitimate_ maximum, not a comfortable
   large number. The ceiling is what turns "reassign one account" into a hard stop
   against "reassign every account this rep owns".

5. **Scope by profile/permission set** so human-driven and agent-driven calls to the
   same action can carry different rules.

6. **Deploy** the metadata (`sf project deploy start`). Policy changes ride the same
   review/CI pipeline as code (ADR-003) — never edit policy live in production.

## Verify

- `PolicyRegistry.resolve('<name>')` returns the policy.
- A call within all limits ALLOWs; one exceeding the ceiling ROLLBACKs; one over the
  rate limit is THROTTLED; a bad shape is BLOCKed by schema.

## Rules to honor

- New policy fields must default to the most restrictive safe value (RULES.md #5) and
  be documented in `docs/policy-configuration.md` in the same PR (RULES.md #13).
