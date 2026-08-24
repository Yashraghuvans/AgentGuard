# Testing Strategy

> **Status:** drafted — the coverage/scenario matrix becomes mandatory at v0.3
> when flow tests activate. See `scripts/ci/run-flow-scenarios.js` for the
> required scenario list.

## Two Layers

1. **Unit tests** — one test class per gate, isolated contracts, stubbed
   dependencies. Positive + negative + bulk (1 and 200 records) + user-context
   (`System.runAs` with a real low-privilege user) paths.
2. **Flow / integration tests** — full chain against a real scratch org with real
   deployed `Guard_Policy__mdt` records: SchemaValidator → AccessGate →
   RateLimiter → RollbackGuard → AuditPublisher. Assertions are outcome-oriented:
   was DML committed? Was an audit event published?

## Coverage & Scenario Matrix

Every threat row in [threat-model.md](threat-model.md) must map to a currently
passing test. An entry here with no green check in CI is a documentation lie.

| Threat / Requirement                                      | Test type   | Test class                                     |
| --------------------------------------------------------- | ----------- | ---------------------------------------------- |
| Prompt-injected bulk mutation via single-record contract  | Flow        | TerritoryReassignFlowTest                      |
| User lacks field-level access to mutated field            | Unit        | AccessGateTest                                 |
| Agent exceeds rate limit in rolling window                | Flow        | TerritoryReassignFlowTest                      |
| Malformed payload missing required schema field           | Unit        | SchemaValidatorTest                            |
| Partial failure mid-bulk triggers full rollback           | Unit + Flow | RollbackGuardTest + chain scenario             |
| Every BLOCK produces exactly one audit event              | Flow        | TerritoryReassignFlowTest + AuditPublisherTest |
| Bulk 200-record payload processes without governor errors | Unit        | AccessGateTest, RateLimiterTest                |

## Standards

- 90% minimum on `core/` classes, CI-enforced (`scripts/ci/check-coverage.js`)
- `given_when_then` test method names
- Single shared `TestDataFactory` for all fixtures
- Scratch orgs created fresh per run and deleted after — never shared state
