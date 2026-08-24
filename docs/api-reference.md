# API Reference

> **Status:** drafted — generated from ApexDoc headers as classes land (v0.1+).

## `AgentGuard` (facade)

| Member             | Signature                                                        | Notes                                                                           |
| ------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `wrap()`           | `static GuardResult wrap(String policyName, String payloadJson)` | Single entry point. Fail-closed: any internal exception returns a BLOCK result. |
| `BlockedException` | inner exception class                                            | Thrown by callers when `GuardResult.isAllowed == false`.                        |

## `GuardResult`

| Field       | Type      | Notes                                                                          |
| ----------- | --------- | ------------------------------------------------------------------------------ |
| `isAllowed` | `Boolean` |                                                                                |
| `reason`    | `String`  | Always populated on BLOCK/THROTTLE — a BLOCK without a reason string is a bug. |
| `decision`  | `String`  | `ALLOW` / `BLOCK` / `THROTTLED`                                                |

## Gate classes

Internal contracts for `SchemaValidator`, `AccessGate`, `RateLimiter`,
`RollbackGuard`, `AuditPublisher` are documented in-class with ApexDoc and
published here as each class ships. Direct external use of gates is discouraged —
use the facade (ADR-004).
