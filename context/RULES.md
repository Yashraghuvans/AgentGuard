# RULES.md

Hard boundaries / non-negotiables for contributors and AI agents. Violations block
merge regardless of how good the surrounding change is.

## Merge Gates

1. No PR merges without a passing CI run: lint, PMD static analysis, and full test suite.
2. Coverage below **90%** on `core/` classes fails CI — not just Salesforce's 75%
   deploy minimum.
3. Every gate class needs at least one **negative** test proving it correctly blocks
   a bad payload — an ALLOW-only test suite is not acceptable for a security tool.
4. Branches must be up to date with `main` before merge.

## Security Invariants

5. No policy default may be permissive-by-default; every new `Guard_Policy__mdt`
   field must default to the most restrictive safe value.
6. Never weaken a CRUD/FLS check to make a test pass — fix the test's user context.
7. Never remove or bypass the Savepoint/rollback boundary in `RollbackGuard`.
8. Evaluation exceptions fail closed (BLOCK), never open (ALLOW) — see ADR-002.
9. No secrets, org credentials, or real org data in commits, fixtures, or example
   scripts — enforced by pre-commit secret scanning and reviewed manually.

## Change Discipline

10. Breaking changes to the public `AgentGuard.wrap()` signature require a major
    version bump and a migration note in `CHANGELOG.md`.
11. Security-relevant changes (`AccessGate`, `RollbackGuard`, `SchemaValidator`)
    require review from a second maintainer, human or not — including on `sec/*`
    branches. Solo-maintainer self-review protocol is defined in `GOVERNANCE.md`.
12. Every new public method in `core/` requires a corresponding unit test in the
    same PR — no exceptions.
13. All new policy fields on `Guard_Policy__mdt` must be documented in
    `docs/policy-configuration.md` in the same PR.
14. Threat-model changes ride along with behavior changes: if a PR changes a gate's
    behavior, it updates `docs/threat-model.md` in the same PR.
15. Conventional Commits required:
    `feat(rate-limiter): add sliding window support`,
    `fix(access-gate): correct FLS check on polymorphic lookups`,
    `sec(schema-validator): reject payloads with unknown top-level keys`.

## Scope Discipline

16. No feature without a concrete threat or workflow it mitigates (see `LIMITS.md`
    and `docs/threat-model.md`). Scope creep is how security tools become unmaintainable.
17. No external callouts, npm dependencies, or managed-package dependencies in the
    core enforcement path.
