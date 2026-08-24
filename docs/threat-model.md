# Threat Model (STRIDE)

> **Status:** drafted — maintained per RULES.md #14: updated in the same PR that
> changes a gate's behavior. A stale threat model is worse than none.

| STRIDE                 | Threat in this context                                                                  | Mitigating component                                                                                                  |
| ---------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Spoofing               | Agent session impersonates a higher-privileged user context                             | `AccessGate` — always evaluates WITH USER_MODE against the real running-user context, never a claimed or elevated one |
| Tampering              | Prompt-injected instruction reshapes a payload into a bulk or out-of-contract mutation  | `SchemaValidator` — rejects payloads not matching the declared contract before business logic                         |
| Repudiation            | Agent denies issuing a destructive call with no record to prove otherwise               | `AuditPublisher` — every decision published as an immutable Platform Event with actor, payload hash, timestamp        |
| Information Disclosure | Agent queries/returns fields the requesting user cannot see                             | `AccessGate` — FLS enforcement strips or blocks inaccessible fields on read paths                                     |
| Denial of Service      | Misbehaving agent floods an action, exhausting governor limits or downstream systems    | `RateLimiter` — sliding-window per-agent/per-action throttling                                                        |
| Elevation of Privilege | Partially-successful bulk mutation leaves inconsistent state enabling unintended access | `RollbackGuard` — Savepoint boundary and max-record ceiling ensure atomic, bounded mutations                          |

## Explicit Non-Goals

See [LIMITS.md](../LIMITS.md) and the risk register: no semantic prompt-injection
detection, no Trust Layer replacement, not an identity control.

## Test Coverage Matrix

Each threat row must map to a currently-passing automated test (see
[testing.md](testing.md)). A matrix entry without a green check in CI is a
documentation lie waiting to be caught.
