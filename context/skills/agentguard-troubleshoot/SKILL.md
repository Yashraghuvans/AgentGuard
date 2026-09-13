---
name: agentguard-troubleshoot
description: Diagnose why an AgentGuard SF call was blocked, throttled, or rolled back, and decide whether the fix is a policy change or a genuine security stop. Use when a user says "my agent action was blocked", "AgentGuard is rejecting my call", "why is this THROTTLED", "unexpected rollback", or is decoding a GuardResult reason / audit event.
---

# Troubleshoot an AgentGuard decision

## First principle

AgentGuard fails closed. A block is the system working, not necessarily a bug. Decide
**"should this call have been allowed?"** before changing anything — never weaken a gate
to make a call pass (RULES.md #6).

## Read the decision

The `GuardResult` (and the matching `AgentGuard_Audit__e` event) tells you which gate
stopped the call via `gateName` + `decision` + `reason`.

| decision    | gateName   | Meaning                                                                                                                      | Likely fix                                                                                 |
| ----------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `BLOCK`     | `SCHEMA`   | Payload shape didn't match `SchemaContract__c` (missing/extra/typed-wrong field, or bulk shape for a single-record contract) | Fix the caller's payload, or correct the contract if the shape is legitimately valid       |
| `BLOCK`     | `ACCESS`   | Running user lacks CRUD/FLS on the target object/field                                                                       | Grant the user the permission via profile/perm set — **not** by relaxing the gate          |
| `THROTTLED` | `RATE`     | Calls exceeded `RateLimitPerMinute__c` in the window                                                                         | Confirm it's legitimate volume; raise the limit deliberately, or fix a runaway caller loop |
| `ROLLBACK`  | `ROLLBACK` | Call exceeded `MaxRecordsPerCall__c`, or business logic threw after the savepoint                                            | Reduce batch size, or raise the ceiling if the larger batch is genuinely expected          |
| `BLOCK`     | `FACADE`   | An evaluation exception was caught and failed closed (ADR-002)                                                               | A bug in AgentGuard or a missing policy — inspect the reason string; fix the root cause    |

## Decision tree

1. **Is there a policy?** No `Guard_Policy__mdt` for the name passed to `wrap()` →
   fail-closed FACADE block. Create one (`agentguard-policy-config`).
2. **SCHEMA block?** Compare the serialized payload to `SchemaContract__c`. A bulk-shaped
   payload against a single-record contract is the canonical prompt-injection stop —
   usually you want to keep the block.
3. **ACCESS block?** Reproduce as the real running user with `System.runAs()`. If the
   user truly should have access, fix their permissions, not the gate.
4. **THROTTLED?** Check the audit event volume for the agent/action. Legitimate burst →
   raise `RateLimitPerMinute__c`/window. Otherwise the throttle is doing its job.
5. **ROLLBACK?** Check record count vs `MaxRecordsPerCall__c` and whether the business
   logic threw. The ceiling exists to bound blast radius — raise it only intentionally.

## What NOT to do

- Do not bypass `wrap()` or call a single gate to "get around" a block.
- Do not lower a ceiling/limit/contract just to make a test or demo pass.
- Do not treat a FACADE exception block as "flaky" — it's a caught error; find it.

## Confirm the fix

Re-run with the corrected payload/permission/policy and verify the audit event now shows
the expected decision. Keep the negative test that proves the original block still blocks.
