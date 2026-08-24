# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned — v0.1 Core Gate

- `AgentGuard.cls` — public `wrap()` facade with fail-closed boundary (ADR-002)
- `SchemaValidator.cls` — schema contract validation of AI-originated payloads
- `AccessGate.cls` — CRUD/FLS enforcement `WITH USER_MODE` against running user
- `AuditPublisher.cls` — real-time `AgentGuard_Audit__e` Platform Event on every decision
- `GuardResult.cls` / `GuardPolicy.cls` — value types
- Unit tests: positive + negative + bulk paths per gate class

### Planned — later milestones

- v0.3: `RateLimiter` (Platform Cache, sliding window), `RollbackGuard` (Savepoint + record ceiling)
- v0.6: `Guard_Policy__mdt` declarative policy wiring
- v0.8: `guardAuditDashboard` LWC, `sf agentguard` CLI plugin
- v1.0: docs site, 2GP unlocked package, 90%+ coverage gate green in CI

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
