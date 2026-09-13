---
name: agentguard-integrate
description: Wrap a Salesforce @InvocableMethod (or any agent-callable Apex action) with AgentGuard SF so every AI-originated call is schema-validated, CRUD/FLS-checked, rate-limited, rolled back on failure, and audited. Use when a user says "make this action agent-safe", "wrap my invocable method", "add AgentGuard to this class", or is integrating AgentGuard for the first time.
---

# Integrate AgentGuard into an Apex action

## Goal

Add the AgentGuard gate chain to an existing action in one line, without refactoring
the surrounding business logic.

## Prerequisites

- AgentGuard SF is deployed/installed in the org (classes `AgentGuard`, `GuardResult`, etc. exist).
- A `Guard_Policy__mdt` record exists for the action (if not, run the
  `agentguard-policy-config` skill first — an action with no policy fails closed).

## Steps

1. **Identify the entry point.** Find the `@InvocableMethod` (or the public method the
   agent tool-call reaches). It receives a `List<Request>`.

2. **Add the wrap call as the first statement**, before any DML or business logic:

   ```apex
   @InvocableMethod(label='Update Account Territory')
   public static List<Result> execute(List<Request> requests) {
       GuardResult check = AgentGuard.wrap(
           'UpdateAccountTerritory',        // Guard_Policy__mdt DeveloperName
           JSON.serialize(requests)         // raw AI-originated payload
       );
       if (!check.isAllowed) {
           throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
       }
       return TerritoryService.reassign(requests); // unchanged
   }
   ```

3. **If the business logic can throw and you want automatic rollback**, use the
   execute variant instead of managing the savepoint yourself:

   ```apex
   GuardResult result = AgentGuard.wrapAndExecute(
       'UpdateAccountTerritory',
       JSON.serialize(requests),
       (GuardResult allowed) => { ... business logic ...; return allowed; }
   );
   ```

   `wrap()` opens a savepoint and attaches it to the returned `GuardResult`; on a caught
   exception call `AgentGuard.rollback(result)`.

4. **Do NOT** call `SchemaValidator`, `AccessGate`, `RateLimiter`, or `RollbackGuard`
   directly. The single `wrap()` facade is the only supported entry point (ADR-004) —
   calling gates individually is how integrations end up partially enforced.

5. **Bulk safety.** The payload is a `List<Request>`. Never rewrite the action to assume
   a single record; the gates batch across the list.

## Verify

- A well-formed, permitted call returns `isAllowed == true` and executes normally.
- A malformed / over-privileged / bulk-shaped payload returns `isAllowed == false`
  with a `reason` and produces one `AgentGuard_Audit__e` event.
- Add at least one **negative** test proving the block (required by RULES.md #3).

## Common mistakes

- Wrapping _after_ DML has already run — wrap must be the first thing.
- Passing a hand-built map instead of the real serialized request — the schema contract
  validates the actual agent payload shape.
- Forgetting the policy record — no policy means fail-closed BLOCK.
