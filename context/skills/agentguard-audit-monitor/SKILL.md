---
name: agentguard-audit-monitor
description: Observe what AI agents attempted through AgentGuard SF by consuming the AgentGuard_Audit__e Platform Event — subscribe in Apex/Flow/LWC, or persist events for querying. Use when a user asks "what have agents been doing", "show blocked calls", "monitor agent actions", "build an audit dashboard", or wants a durable record of ALLOW/BLOCK/THROTTLED decisions.
---

# Monitor AgentGuard audit events

## Goal

Get visibility into every decision AgentGuard made. One `AgentGuard_Audit__e` event is
published per wrapped call — ALLOW, BLOCK, THROTTLED, or ROLLBACK.

## Key fact (why it's an event, not a table)

Platform Events publish **outside** the transaction's rollback boundary (ADR-001). So a
BLOCK that rolls back the DML still leaves a durable audit record. This also means the
events are **not** queryable via SOQL after the fact — you must subscribe and persist
them if you need history.

## Event fields

`ActionName__c`, `PolicyName__c`, `GateName__c`, `Decision__c` (ALLOW/BLOCK/THROTTLED/ROLLBACK),
`Reason__c`, `ActorId__c`, `AgentKey__c`, `PayloadHash__c` (hash, never raw payload),
`LatencyMs__c`, `Flagged__c`.

## Options

### 1. Real-time in-org view (LWC)

Subscribe to `/event/AgentGuard_Audit__e` via `lightning/empApi` and render live decision
counts / a recent-events feed. This is the optional `guardAuditDashboard` component.

### 2. Persist for querying (Apex trigger + custom object)

If the org needs long-term queryable history or compliance retention, add a trigger on
`AgentGuard_Audit__e` that inserts a custom object row per event. AgentGuard ships events
only; persistence is the adopter's choice (documented in `docs/architecture.md`).

```apex
trigger AgentGuardAuditTrigger on AgentGuard_Audit__e(after insert) {
  List<Guard_Audit_Log__c> rows = new List<Guard_Audit_Log__c>();
  for (AgentGuard_Audit__e e : Trigger.new) {
    rows.add(
      new Guard_Audit_Log__c(
        Action__c = e.ActionName__c,
        Decision__c = e.Decision__c,
        Reason__c = e.Reason__c,
        Actor__c = e.ActorId__c,
        PayloadHash__c = e.PayloadHash__c,
        LatencyMs__c = e.LatencyMs__c
      )
    );
  }
  insert rows;
}
```

### 3. Terminal tail (SF CLI companion, optional)

`sf agentguard audit tail` / `sf agentguard audit summary` stream and summarize events
without leaving the terminal — useful during testing and spot-checks.

## Guardrails

- Delivery is at-least-once; consumers must tolerate duplicate events.
- Treat a BLOCK as already-enforced synchronously even if dashboard visibility lags.
- Never reconstruct or log the raw payload — only `PayloadHash__c` is available by design.
