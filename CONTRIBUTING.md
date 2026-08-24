# Contributing to AgentGuard SF

Thank you for contributing to a security-critical Apex framework. Read
[AGENTS.md](AGENTS.md) first — it defines the philosophy and hard boundaries every
change must respect (human and AI contributors alike).

## Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Salesforce CLI (`sf`) | v2.x | `npm install -g @salesforce/cli` |
| Node.js | 20+ | see `.nvmrc` |
| Java | 17+ | required by Prettier-Apex plugin and PMD |

## Local Setup

```bash
git clone https://github.com/yashraghuvanshi/agentguard-sf
cd agentguard-sf
npm install                 # installs Prettier, ESLint, Husky hooks
sf org login web            # or: sf org login jwt for headless
sf org create scratch -f config/project-scratch-def.json -a ag-dev
sf project deploy start -o ag-dev
```

## Before Opening a PR

```bash
npm run lint                # Prettier check + ESLint
npm run pmd:apex            # PMD static analysis (downloads PMD into ./tools on first run)
sf apex run test -o ag-dev --code-coverage --result-format json --output-dir ./test-results --wait 30
node scripts/ci/check-coverage.js ./test-results 90
```

CI enforces all of the above against a fresh scratch org. Local failures will fail CI.

## Branch Strategy

| Branch | Purpose |
| --- | --- |
| `main` | Protected, deploy-ready at all times |
| `develop` | Integration branch for the next release |
| `feat/<name>` | New capability |
| `fix/<name>` | Bug fix |
| `sec/<name>` | Security-relevant change — requires second review (see GOVERNANCE.md) |

## Commit Conventions

Conventional Commits, enforced by review:

```
feat(rate-limiter): add sliding window support
fix(access-gate): correct FLS check on polymorphic lookups
sec(schema-validator): reject payloads with unknown top-level keys
docs(policy-configuration): document MaxRecordsPerCall default
```

## Testing Expectations

- Every gate class change includes positive **and negative** tests.
- New public methods in `core/` ship with unit tests in the same PR (RULES.md #12).
- Use `TestDataFactory` patterns for fixtures; never hand-roll users/records inline.
- Bulk paths are tested at 1 record and 200 records minimum.

## Proposing a `Guard_Policy__mdt` Schema Change

1. Open an issue first with the threat/workflow the field addresses.
2. The PR adds the field with its **most restrictive safe default**.
3. The PR updates `docs/policy-configuration.md` in the same PR (RULES.md #13).
4. If the field changes enforcement semantics, update `docs/threat-model.md` too.

## AI Coding Agents

You are welcome here — after reading [AGENTS.md](AGENTS.md). State your
implementation plan in the PR description before writing tests, reproduce bugs with
failing tests first, and flag every assumption you made.

## PR Checklist (mirrors the PR template)

- [ ] Tests added/updated, including a negative case for any new gate behavior
- [ ] Docs updated (policy fields → policy-configuration.md)
- [ ] CHANGELOG.md entry included in this PR
- [ ] No policy default weakened
- [ ] Conventional Commits used
