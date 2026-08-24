<!--
AI coding agents: read AGENTS.md first. State your implementation plan in this
PR description BEFORE the tests, per AGENTS.md.
-->

## What & Why

<!-- Link the issue. One line on what changed and the threat/workflow it addresses. -->

Fixes #

## Implementation Plan

<!-- The plan stated before code, per AGENTS.md "Before Writing Code". -->

## Security Impact

- [ ] This change touches `AccessGate`, `RollbackGuard`, or `SchemaValidator` (requires `sec/*` branch + second review)
- [ ] This change adds/removes/reorders gates in the request lifecycle
- [ ] No security-relevant surface touched

If a gate changed: trace each ALLOW/BLOCK path by hand and summarize here.

## Checklist (RULES.md)

- [ ] Tests added/updated — including at least one **negative** test for new gate behavior
- [ ] New public methods in `core/` have unit tests in this PR
- [ ] Bulk paths tested (1 record + 200 records)
- [ ] New `Guard_Policy__mdt` fields default to most restrictive safe value
- [ ] `docs/policy-configuration.md` updated for any policy field changes
- [ ] `docs/threat-model.md` updated if gate behavior changed
- [ ] `CHANGELOG.md` entry included in this PR
- [ ] No policy default weakened anywhere in this diff
- [ ] Conventional Commits used
