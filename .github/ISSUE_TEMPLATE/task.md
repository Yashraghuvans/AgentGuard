---
name: Development task
about: Track a planned unit of work from the blueprint roadmap
title: '[type(scope): short summary]'
labels: ''
assignees: ''
---

> AI coding agents: read [AGENTS.md](../blob/main/AGENTS.md) before working on
> this task. State your implementation plan before writing tests.

## Summary

<!-- One paragraph: what this delivers and why it matters. -->

## Blueprint Reference

<!-- Traceability: which blueprint section / threat-model row does this satisfy?
     e.g. "Section 4.2 Core Components", "STRIDE row: Tampering". -->

## Deliverables

<!-- Concrete artifacts this issue produces. -->

- [ ] ...

## Acceptance Criteria

<!-- The PR merging this issue must satisfy all of these. -->

- [ ] Unit tests added — positive AND negative paths (`given_when_then` naming)
- [ ] Bulk paths tested (1 record + 200 records) where applicable
- [ ] Coverage ≥ 90% for touched `core/` classes (CI-enforced)
- [ ] Docs updated (`docs/policy-configuration.md` if any `Guard_Policy__mdt`
      field changed; `docs/threat-model.md` if gate behavior changed)
- [ ] `CHANGELOG.md` entry included in the same PR
- [ ] Conventional Commits used; no policy default weakened

## Security Checklist

<!-- Required for anything touching the enforcement path. -->

- [ ] Does not weaken CRUD/FLS enforcement or the Savepoint boundary
- [ ] Preserves fail-closed behavior (exceptions = BLOCK)
- [ ] Introduces no external callouts into the core path
- [ ] No secrets or real org data in fixtures/examples

## Dependencies

<!-- e.g. "Blocked by #12", "Blocks #14". -->

## Assumptions & Open Questions

<!-- Flag every assumption made while scoping this task. -->
