# AGENTS.md

## Philosophy: Direct, Don't Vibe

You are contributing to a security-critical Apex framework. Every change must be
deliberate, typed, tested, and traceable to a stated requirement. Do not guess at
Salesforce platform behavior — verify against official docs or existing test coverage.

## Non-Negotiable Boundaries

1. Never weaken a CRUD/FLS check to make a test pass. If a test fails because of
   access enforcement, fix the test's user context — not the enforcement.
2. Never remove or bypass the Savepoint/rollback boundary in RollbackGuard.
3. Every new public method in `force-app/main/default/classes/core/` requires a
   corresponding unit test in the same PR — no exceptions, no "will add tests later".
4. Do not introduce external callouts into the core enforcement path (see LIMITS.md).
5. All new policy fields on Guard_Policy__mdt must be documented in
   docs/policy-configuration.md in the same PR.

## Before Writing Code

1. Read SKILLS.md for the domain context you need.
2. Read RULES.md for constraints specific to the area you're touching.
3. State your implementation plan in the PR description before writing tests.

## Workflow AI Agents Must Follow

1. Reproduce the bug/requirement with a failing test first.
2. Implement the minimal change to pass it.
3. Run the full local test suite before proposing the diff.
4. Flag any assumption you made explicitly in the PR description.

## Repo Map (where things live)

| Path | Purpose |
| --- | --- |
| `force-app/main/default/classes/core/` | Gate classes: AgentGuard facade + SchemaValidator, AccessGate, RateLimiter, RollbackGuard, AuditPublisher |
| `force-app/main/default/classes/models/` | Value types: GuardResult, GuardPolicy |
| `force-app/main/default/classes/tests/` | Apex unit tests |
| `force-app/main/default/objects/Guard_Policy__mdt/` | Declarative policy configuration |
| `force-app/main/default/platformEvents/AgentGuard_Audit__e/` | Audit event definition |
| `examples/` | Copy-paste integration projects |
| `docs/` | Hosted documentation (GitHub Pages) |
| `scripts/ci/` | CI helpers (coverage gate, PMD runner, flow scenarios) |

## Request Lifecycle You Are Working Inside

Every wrapped call passes through: **SchemaValidator → AccessGate → RateLimiter →
RollbackGuard → business logic → AuditPublisher**. There is no bypass path. Any
change that adds, removes, or reorders gates is a security-relevant change and
follows RULES.md #11.

Fail closed everywhere: if unsure whether a path should ALLOW or BLOCK, BLOCK.
