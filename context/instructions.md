# AgentGuard SF — AI Context Pack

> **Read this first.** This folder gives an AI assistant everything it needs to help a
> user **adopt, configure, operate, or contribute to** AgentGuard SF — without reading
> the whole codebase. If you are an AI acting for a user who has AgentGuard installed
> (or is evaluating it), start here.

## What AgentGuard SF is

A lightweight, open-source **Apex firewall** between AI agents (Agentforce, MCP clients,
custom LLM integrations) and the Salesforce database. It wraps any `@InvocableMethod`
with a single call and treats every agent-issued action as untrusted input by default:

```apex
GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
return TerritoryService.reassign(requests); // your logic, unchanged
```

Every wrapped call runs the same gate chain, in order, with **no bypass path**:

**SchemaValidator → AccessGate → RateLimiter → RollbackGuard → business logic → AuditPublisher**

| Gate              | Enforces                                                                          |
| ----------------- | --------------------------------------------------------------------------------- |
| `SchemaValidator` | Payload shape matches the action's declared contract (`SchemaContract__c`)        |
| `AccessGate`      | CRUD/FLS `WITH USER_MODE` against the **running user**, never an elevated context |
| `RateLimiter`     | Sliding-window per-agent/per-action throttle, Platform Cache-backed               |
| `RollbackGuard`   | Savepoint boundary + `MaxRecordsPerCall__c` ceiling                               |
| `AuditPublisher`  | Publishes an `AgentGuard_Audit__e` Platform Event for **every** decision          |

## Non-negotiable design invariants (never violate when helping)

1. **Fail closed.** Any evaluation exception is a `BLOCK`, never an ALLOW (ADR-002).
2. **Restrictive by default.** No policy field defaults to permissive.
3. **Running-user context.** Access checks use the invoking user, not a service/admin context.
4. **Audit always.** Every ALLOW/BLOCK/THROTTLED/ROLLBACK produces exactly one audit event.
5. **No external callouts** in the enforcement path.
6. **Structural, not semantic.** AgentGuard does not do NLP prompt-injection detection —
   it enforces schema, CRUD/FLS, rate, and rollback. See `LIMITS.md`.

## How to use this folder

| File                          | Use it when you need…                                                    |
| ----------------------------- | ------------------------------------------------------------------------ |
| `instructions.md` (this file) | Orientation and the mental model                                         |
| `SKILLS.md`                   | Salesforce domain knowledge required to reason correctly about the gates |
| `RULES.md`                    | Hard boundaries for changing the code (merge gates, security invariants) |
| `LIMITS.md`                   | What AgentGuard deliberately does **not** do — set honest expectations   |
| `GOVERNANCE.md`               | Who merges, how decisions and security reviews work                      |
| `skills/`                     | Task-specific playbooks a user's AI can execute (see below)              |

## Skills (task playbooks in `skills/`)

Each subfolder is a self-contained skill with a `SKILL.md`. Point your reasoning at the
one that matches the user's intent:

| Skill                      | Trigger                                                                        |
| -------------------------- | ------------------------------------------------------------------------------ |
| `agentguard-integrate`     | "wrap my invocable action", "make this agent action safe", first install       |
| `agentguard-policy-config` | "configure a policy", "set a rate limit / record ceiling", `Guard_Policy__mdt` |
| `agentguard-audit-monitor` | "see what agents did", query/subscribe to `AgentGuard_Audit__e`                |
| `agentguard-troubleshoot`  | "my call was blocked", decode a decision + reason                              |

## Public API surface (stable contract)

- `AgentGuard.wrap(String policyName, String payloadJson) → GuardResult`
- `AgentGuard.wrapAndExecute(policyName, payloadJson, RollbackGuard.GuardResultCallback) → GuardResult`
- `AgentGuard.rollback(GuardResult) → GuardResult`
- `AgentGuard.BlockedException(reason, decision, gateName)`

`GuardResult` fields: `isAllowed`, `decision` (`ALLOW`/`BLOCK`/`THROTTLED`/`ROLLBACK`),
`reason`, `policyName`, `actionName`, `gateName`, `flagged`.

## Guard_Policy__mdt fields

`IsActive__c`, `SchemaContract__c`, `TargetSObjectType__c`, `Operation__c`,
`MaxRecordsPerCall__c`, `RateLimitPerMinute__c`, `RateLimitWindowSeconds__c`,
`AllowedProfiles__c`, `AllowedPermissionSets__c`.

## AgentGuard_Audit__e fields

`ActionName__c`, `PolicyName__c`, `GateName__c`, `Decision__c`, `Reason__c`,
`ActorId__c`, `AgentKey__c`, `PayloadHash__c`, `LatencyMs__c`, `Flagged__c`.

> Payloads are hashed, never stored raw — do not suggest logging raw payloads.
