# SKILLS.md

Required domain knowledge to work on this repo. If any statement here conflicts
with current official Salesforce documentation, the documentation wins — update
this file in the same PR.

## Domain 1: Salesforce Data Security Model

- CRUD/FLS/Sharing are three separate enforcement layers; `WITH USER_MODE` on SOQL
  covers object/field-level access but NOT sharing rules on DML — verify which layer
  a given check actually covers before claiming a payload is 'safe'.
- `Security.stripInaccessible()` is the supported way to strip fields a user cannot
  access from a payload rather than throwing — used in AccessGate for read paths.
- Apex runs in system context by default: an invocable action without explicit
  user-mode checks grants every caller admin-equivalent data reach. This default
  is exactly what AgentGuard exists to close.

## Domain 2: Invocable Actions & Agentforce / Agent Tool-Calling

- `@InvocableMethod` request/response shapes are what agent tool-calling frameworks
  serialize against; a malformed contract is a common source of an agent
  'hallucinating' a call shape that doesn't match reality.
- Agent-issued calls should be treated as originating from the running user's
  context, not a system/elevated context, unless a policy explicitly says otherwise.
- Invocable methods receive a `List<Request>` — bulk-safety is part of the contract,
  not an optimization.

## Domain 3: Platform Events & Async Audit Logging

- Platform Events publish outside the triggering transaction's rollback boundary
  when published via `EventBus.publish` — this is why audit logs still exist even
  when the underlying DML in the transaction is rolled back (basis of ADR-001).
- Delivery is at-least-once; consumers must tolerate duplicates. Treat BLOCK as
  synchronous enforcement even though dashboard visibility can lag seconds.

## Domain 4: Governor Limits & Bulkification

- RateLimiter and RollbackGuard must remain bulk-safe for list-based Invocable
  requests; never assume a single-record payload.
- Per-record looping inside gates is a design bug — schema and access checks batch
  across the list so overhead stays flat at ~200 records (Section 15 budget).

## Domain 5: Policy Metadata & Packaging

- Custom Metadata Types are deployed like code (ADR-003) — never suggest runtime-
  editable Custom Settings for policy storage; that bypasses review pipelines.
- Shipping model is a 2GP unlocked package built by `release.yml`; keep metadata
  packageable: no hardcoded org IDs, no dependency on unpackaged org config.
