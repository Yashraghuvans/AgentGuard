# Testing Strategy

> **Status:** Complete at v1.0. The coverage/scenario matrix is mandatory.

## Two Layers

### 1. Unit Tests — Isolate Each Gate Class

Each `core/` class gets its own test class, testing only that class's contract. Dependencies on other gates are avoided or stubbed so a failure always points at exactly one class.

**Requirements per gate class:**

- **Positive Path** — At least one test proving correct behavior on a well-formed, permitted payload
- **Negative Path** — At least one test proving it correctly BLOCKS on a malformed, over-privileged, or rate-exceeding payload (this is the more important half for a security tool)
- **Bulk / Edge Cases** — Test with empty list, single record, and bulk list (200 records) — Apex logic only tested with one record is a classic source of production governor-limit failures
- **User-Context Tests** — Use `System.runAs()` with a purpose-built low-privilege test user to prove AccessGate actually restricts a real restricted user, not just the test-running admin

### 2. Flow / Integration Tests — Whole-Chain Scenarios

Flow tests validate the full request lifecycle end-to-end: SchemaValidator → AccessGate → RateLimiter → RollbackGuard → AuditPublisher, running against a real scratch org with real `Guard_Policy__mdt` records deployed, not stubs.

**Requirements:**

- **Scratch-Org Based** — Deploy source and seed `Guard_Policy__mdt` + test data via Apex setup script, exactly as a real org would be configured
- **Outcome-Oriented Assertions** — Each scenario asserts on the final outcome the way an actual caller would observe it: was the DML committed, was an exception thrown, was an audit event published — not internal implementation details
- **Audit Trail Verification** — Every scenario ends by querying `AgentGuard_Audit__e`-derived log records (or captured Platform Event in test context) to prove the decision was actually recorded, not just correctly computed
- **Clean State Per Run** — Scratch orgs are created fresh per CI run and deleted after — flow tests never share state with each other or with prior runs

## Coverage & Scenario Matrix

Every threat row in [threat-model.md](threat-model.md) must map to a currently passing test. An entry here with no green check in CI is a documentation lie.

| Threat / Requirement                                       | Test Type   | Test Class / Method                                                                                                                |
| ---------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Prompt-injected bulk mutation via single-record contract   | Flow        | `TerritoryReassignFlowTest.given_injectedBulkChurnPayload_when_agentInvokes_then_blockedAndAudited()`                              |
| User lacks field-level access to a mutated field           | Unit        | `AccessGateTest.given_readOnlyUser_when_modifiesAccount_then_blocksWithReason()`                                                   |
| Agent exceeds rate limit in rolling window                 | Flow        | `TerritoryReassignFlowTest.given_repeatedRapidCalls_when_rateLimitExceeded_then_throttledAfterThreshold()`                         |
| Malformed payload missing required schema field            | Unit        | `SchemaValidatorTest.given_missingRequiredField_when_validated_then_blocksWithReason()`                                            |
| Partial failure mid-bulk triggers full rollback            | Unit + Flow | `RollbackGuardTest.given_executeWithRollback_when_callbackThrows_then_rollsBackAndReturnsRollback()` + `TerritoryReassignFlowTest` |
| Every BLOCK produces exactly one audit event               | Flow        | `AgentGuardTest.given_blockedCall_when_wrapped_then_auditEventIsBlocked()` + `TerritoryReassignFlowTest`                           |
| Bulk 200-record payload processes without governor errors  | Unit        | `AccessGateTest.given_bulkPayload_when_evaluated_then_handles200RecordsWithoutLimitError()`                                        |
| Cache outage triggers allow-and-log (not silent fail-open) | Unit        | `RateLimiterTest.given_cachePartitionMissing_when_checked_then_allowFlagged()`                                                     |
| Unknown schema keys rejected                               | Unit        | `SchemaValidatorTest.given_unknownField_when_validated_then_blocksWithReason()`                                                    |
| Type mismatch (string vs number) rejected                  | Unit        | `SchemaValidatorTest.given_wrongType_when_validated_then_blocksWithReason()`                                                       |
| Integer range validation (min/max)                         | Unit        | `SchemaValidatorTest.given_integerRangeValidation_when_outOfBounds_then_blocks()`                                                  |
| Enum validation                                            | Unit        | `SchemaValidatorTest.given_enumValidation_when_invalidValue_then_blocks()`                                                         |
| Nullable field handling                                    | Unit        | `SchemaValidatorTest.given_nullableFieldWithNull_when_validated_then_allows()`                                                     |
| Profile scoping restriction                                | Unit        | `AccessGateTest.given_profileRestriction_when_userNotInAllowedProfile_then_blocks()`                                               |
| Permission set scoping restriction                         | Unit        | `AccessGateTest.given_permissionSetRestriction_when_userLacksPermSet_then_blocks()`                                                |
| Disabled policy blocks                                     | Unit        | `AccessGateTest.given_disabledPolicy_when_evaluated_then_blocks()`                                                                 |
| Missing target sObject blocks                              | Unit        | `AccessGateTest.given_missingTargetSObject_when_evaluated_then_blocks()`                                                           |
| Rate limit independent per user                            | Unit        | `RateLimiterTest.given_differentUsers_when_checked_then_independentCounters()`                                                     |
| Rate limit independent per action                          | Unit        | `RateLimiterTest.given_differentActions_when_checked_then_independentCounters()`                                                   |
| Window clamping (min 10s, max 3600s)                       | Unit        | `RateLimiterTest.given_windowClamping_when_windowOutOfBounds_then_clamped()`                                                       |
| Record count ceiling enforced                              | Unit        | `RollbackGuardTest.given_recordCountExceedsLimit_when_opened_then_blocks()`                                                        |
| Zero max records blocks                                    | Unit        | `RollbackGuardTest.given_zeroMaxRecords_when_opened_then_blocks()`                                                                 |
| Rollback on exception                                      | Unit        | `RollbackGuardTest.given_rollbackOnException_when_rolledBack_then_returnsRollbackResult()`                                         |
| Execute with rollback callback success                     | Unit        | `RollbackGuardTest.given_executeWithRollback_when_callbackSucceeds_then_returnsCallbackResult()`                                   |
| Single object counts as 1                                  | Unit        | `RollbackGuardTest.given_singleObjectPayload_when_counted_then_countsAsOne()`                                                      |
| Empty payload counts as 0                                  | Unit        | `RollbackGuardTest.given_emptyPayload_when_counted_then_countsAsZero()`                                                            |
| Facade: valid payload allows with savepoint                | Unit        | `AgentGuardTest.given_validPayload_when_wrapped_then_allowsWithSavepoint()`                                                        |
| Facade: invalid schema blocks at SCHEMA gate               | Unit        | `AgentGuardTest.given_invalidSchema_when_wrapped_then_blocksAtSchemaGate()`                                                        |
| Facade: rate limit blocks at RATE gate                     | Unit        | `AgentGuardTest.given_rateLimitExceeded_when_wrapped_then_blocksAtRateGate()`                                                      |
| Facade: record limit blocks at ROLLBACK gate               | Unit        | `AgentGuardTest.given_recordLimitExceeded_when_wrapped_then_blocksAtRollbackGate()`                                                |
| Facade: wrapAndExecute rolls back on exception             | Unit        | `AgentGuardTest.given_wrapAndExecute_when_callbackThrows_then_rollsBack()`                                                         |
| Facade: unknown policy blocks at ACCESS gate               | Unit        | `AgentGuardTest.given_unknownPolicy_when_wrapped_then_blocksAtFacade()`                                                            |
| Facade: audit event captured in test mode                  | Unit        | `AgentGuardTest.given_auditEventPublished_when_wrapped_then_capturesInTestMode()`                                                  |
| Facade: blocked call produces BLOCKED audit event          | Unit        | `AgentGuardTest.given_blockedCall_when_wrapped_then_auditEventIsBlocked()`                                                         |
| Flow: valid single record allows + audit                   | Flow        | `TerritoryReassignFlowTest.given_validSingleRecord_when_processed_then_allowsAndCapturesAudit()`                                   |
| Flow: business logic throws → rollback + audit             | Flow        | `TerritoryReassignFlowTest.given_businessLogicThrows_when_wrapAndExecute_then_rollsBackAndAudits()`                                |
| Flow: disabled policy blocks + audit                       | Flow        | `TerritoryReassignFlowTest.given_disabledPolicy_when_invoked_then_blocksWithAudit()`                                               |

## Standards

- **90% minimum coverage** on `core/` classes, CI-enforced (`scripts/ci/check-coverage.js`)
- **`given_when_then` test method names** — self-explanatory in CI logs
- **Single shared `TestDataFactory`** for all fixtures — prevents subtle inconsistency bugs
- **Scratch orgs created fresh per run and deleted after** — never shared state
- **Negative tests mandatory** — every gate needs at least one test proving it BLOCKS correctly
- **Test capture mode** — `AuditPublisher.setCaptureMode(true)` for deterministic audit assertions

## Running Tests Locally

```bash
# Deploy to scratch org
sf project deploy start -o myScratchOrg

# Run all tests with coverage
sf apex run test -o myScratchOrg -c -r human --code-coverage --result-format json --output-dir ./test-results

# Check coverage gate (90% on core/)
node scripts/ci/check-coverage.js ./test-results 90
```

## CI Pipeline

See `.github/workflows/ci.yml` for the full pipeline:

1. **Lint & Static Analysis** — Prettier, ESLint, PMD Apex
2. **Unit Tests** — Scratch org, full suite, 90% coverage gate on `core/`
3. **Flow Integration Tests** — Scratch org, seed data, E2E scenarios
4. **Validate-Only Deploy** — Against packaging org (on PR to main)
