# GOVERNANCE.md

This document defines how decisions are made and how authority is exercised in the
AgentGuard SF project.

## Roles

| Role | Who | Authority |
| --- | --- | --- |
| Maintainer (BDFL-lite for v1) | Yash Raghuvanshi | Final say on design, merges, releases |
| Reviewer | Anyone with merged contributions | Approve/review PRs, no merge rights |
| Contributor | Everyone | Propose changes via PR/issue |

## Decision-Making

- **Default:** lazy consensus — a change needs one approving review plus green CI.
- **Tie-break / contested changes:** the maintainer decides. Decisions that are
  non-obvious get recorded as an ADR (see `CHANGELOG.md` history and `docs/`).
- **Breaking changes** to the public `AgentGuard.wrap()` signature or
  `Guard_Policy__mdt` schema require: an ADR, a major version bump, and a migration
  note in `CHANGELOG.md`.

## Merge Authority

1. Every PR requires green CI: lint, PMD static analysis, unit tests, coverage ≥ 90%
   on `core/`, flow/integration scenarios.
2. Branches must be up to date with `main`.
3. The maintainer may not self-merge without CI — including on solo-maintainer days.

### Security-Relevant Changes (`sec/*` branches)

Changes touching `AccessGate`, `RollbackGuard`, `SchemaValidator`, gate ordering in
`AgentGuard.wrap()`, or policy defaults require a **second review**, human or not,
even when the project has a single maintainer.

The documented solo-review protocol until a second maintainer exists:

1. Open the PR and step away for at least 24 hours.
2. Return and perform a fresh read-through of the full diff as if reviewing a
   stranger's code — specifically tracing each ALLOW/BLOCK path by hand.
3. Record in the PR body: date of first pass, date of second pass, and any
   assumption traced. A second review entry with no recorded trace does not count.

## Becoming a Maintainer

Sustained contribution over time: several merged non-trivial PRs, demonstrated
judgment on security-relevant review, and an explicit invitation from the current
maintainer, accepted publicly in an issue. New maintainers start with merge rights
on `feat/*` and `fix/*`; `sec/*` rights follow after three months.

## Changes to This Document

Amendments via PR; substantive changes need a 7-day open comment window before merge.

## Enforcement

Violations of [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) or [RULES.md](RULES.md)
are reported to the maintainer. Security-relevant rule violations (e.g. weakening
a default) result in immediate revert and post-mortem notes in the PR thread.
