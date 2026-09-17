# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `AgentGuard.cls` — the `wrap()` success path hardcoded `flagged=false` and a
  fixed `'ALLOWED_BY_POLICY'` reason on both the returned `GuardResult` and
  the published audit event, silently discarding `RateLimiter`'s degraded-mode
  signal whenever a call succeeded via its fail-open (cache-unavailable)
  path. A call made during a cache outage looked identical to a normal
  ALLOW on the dashboard and in the CLI — exactly the silent-fail-open the
  gate was designed to avoid. Now propagates `RateLimiter`'s `flagged` state
  and reason through to both. Added a regression test
  (`AgentGuardTest.given_rateLimiterFlaggedAllow_when_wrapped_then_finalResultCarriesFlag`),
  bringing the suite from 116 to 117 tests.
- `sf agentguard` CLI plugin — never actually compiled prior to this fix.
  `tsconfig.json` targeted `commonjs` while the source used `import.meta.url`
  (ESM-only), and `package.json`'s `oclif.commands` field was missing
  entirely, so oclif linked the plugin but registered zero commands even
  when pointed at it directly. Also hardened `audit tail` / `audit summary`
  against an upstream jsforce/faye transport quirk that periodically
  rejected an internal long-poll retry promise with no reason — under
  Node's default unhandled-rejection-is-fatal behavior, that crashed the
  process mid-stream. Verified live against a scratch org: both commands
  now build, link, subscribe, and correctly display/aggregate real
  `AgentGuard_Audit__e` events without crashing.

### Added — v0.8.0 core gate + tooling

- `AgentGuard.cls` — public `wrap()` / `wrapAndExecute()` facade with fail-closed boundary (ADR-002)
- `SchemaValidator.cls` — schema contract validation of AI-originated payloads
- `AccessGate.cls` — CRUD/FLS enforcement `WITH USER_MODE` against running user
- `RateLimiter.cls` — Platform Cache sliding-window rate limiting, allow-and-log fallback on cache outage
- `RollbackGuard.cls` — Savepoint boundary + max-records ceiling
- `AuditPublisher.cls` — real-time `AgentGuard_Audit__e` Platform Event on every decision
- `PolicyRegistry.cls` — name → `Guard_Policy__mdt` resolution; unknown names resolve to a
  disabled (all-blocking) policy, never null
- `GuardResult` / `GuardPolicy` — value models (see v0.1 notes below)
- `guardAuditDashboard` LWC — real-time audit event monitor
- `sf agentguard` CLI plugin — `audit tail` and `audit summary` commands
- Tests: 116 tests across all gate, model, and flow classes, 100% pass rate,
  83% test-run coverage / 77% org-wide coverage (last local run: 2026-09-14)

### Added — v0.1 value models (#5)

- `GuardResult` — immutable decision value type (ALLOW/BLOCK/THROTTLED/ROLLBACK);
  non-blank reason enforced at construction for every non-ALLOW outcome.
- `GuardPolicy` — restrictive-by-default policy model: disabled by default,
  zero record ceiling, zero rate budget, empty scoping sets.
- `TestDataFactory` — shared fixture factory for all test suites.

### Added — package version 0.8.0.1 (beta)

- First `AgentGuardSF` unlocked package version cut: `04tfj000000XcL3AAK`
  (`sf package install --package 04tfj000000XcL3AAK`), 83% code coverage,
  passed the coverage check. Installable in sandboxes/scratch/dev orgs;
  not yet promoted for production.

### Roadmap — v1.0

- Promote package version 0.8.0.1 (or a later cut) for production install
- Publish `@agentguard/sf-agentguard` CLI plugin to npm (not yet published)
- Docs site
- 90%+ coverage gate green in CI (currently 83% test-run / 77% org-wide)
- Org-level rate budgets (RL-008), nested schema validation (RL-007) — see
  `docs/risk-register.md`

### Added (scaffolding)

- Repository structure per blueprint Section 7
- AI-aware contributor docs: `AGENTS.md`, `SKILLS.md`, `RULES.md`, `LIMITS.md`
- OSS governance suite: README, LICENSE (MIT), CONTRIBUTING, CODE_OF_CONDUCT,
  SECURITY, GOVERNANCE, PR/issue templates
- GitHub Actions pipelines: `ci.yml`, `release.yml`, `codeql.yml`
- CI helpers: coverage gate (`scripts/ci/check-coverage.js`), PMD runner
  (`scripts/ci/run-pmd.sh`)
- Tooling config: Prettier (Apex plugin), ESLint, Husky pre-commit, PMD ruleset

[Unreleased]: https://github.com/yashraghuvanshi/agentguard-sf/compare/v0.0.0...HEAD
