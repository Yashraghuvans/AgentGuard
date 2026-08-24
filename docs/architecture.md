# Architecture

> **Status:** drafted — component diagram and lifecycle detail land with v0.1.

## Request Lifecycle

Every wrapped call passes through the same chain. There is no bypass path:

```
Agent tool call
      |
      v
SchemaValidator  -> BLOCK?
      |
AccessGate (WITH USER_MODE) -> BLOCK?
      |
RateLimiter (Platform Cache) -> THROTTLE?
      |
RollbackGuard opens Savepoint + record ceiling
      |
Business logic (unchanged)
      |
AuditPublisher -> AgentGuard_Audit__e Platform Event
```

## Components

| Component             | Responsibility                                                                  |
| --------------------- | ------------------------------------------------------------------------------- |
| `AgentGuard.cls`      | Public `wrap()` facade; catches gate exceptions as BLOCK (ADR-002)              |
| `SchemaValidator.cls` | Validates payload against declared action contract                              |
| `AccessGate.cls`      | CRUD/FLS enforcement in running-user context; `stripInaccessible` on read paths |
| `RateLimiter.cls`     | Sliding-window per-agent/per-action throttle (v0.3)                             |
| `RollbackGuard.cls`   | Savepoint boundary + max-records-affected ceiling (v0.3)                        |
| `AuditPublisher.cls`  | Platform Event per ALLOW/BLOCK/THROTTLE decision                                |

## Key Decisions (ADRs)

- **ADR-001:** Platform Events over custom object for audit — survives rollback.
- **ADR-002:** Fail closed — any internal exception is a BLOCK, never an ALLOW.
- **ADR-003:** Custom Metadata Types over Custom Settings — policy changes ride
  the same review pipeline as code.
- **ADR-004:** Single `wrap()` facade — "integrated correctly" == "integrated at all".
- **ADR-005:** MIT license.

Full ADR text ships with the docs site at v1.0.
