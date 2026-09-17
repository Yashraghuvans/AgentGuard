<div align="center">

# AgentGuard SF

**An open-source Apex security firewall between AI agents and Salesforce data.**

Schema validation &nbsp;·&nbsp; CRUD/FLS enforcement &nbsp;·&nbsp; Rate limiting &nbsp;·&nbsp; Transactional rollback &nbsp;·&nbsp; Real-time audit

[![CI](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml)
[![CodeQL](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml)
[![Tests](https://img.shields.io/badge/tests-116%2F116%20passing-brightgreen)](docs/testing.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Demo](#demo-video) · [Overview](#overview--problem-statement) · [Features](#key-features) · [Architecture](#architecture--how-it-works) · [Installation](#installation--setup) · [Configuration](#configuration--usage-examples) · [Testing](#testing--code-coverage)

</div>

---

## Demo Video

<div align="center">

<a href="https://youtu.be/fyR49IBWhlo">
  <img src="https://img.youtube.com/vi/fyR49IBWhlo/maxresdefault.jpg" alt="AgentGuard SF overview video" width="640">
</a>

<sub>▶ 1-minute overview — the problem, the five gates, the guarantees</sub>

</div>

---

## Overview & Problem Statement

AI agents — Agentforce, MCP-connected assistants, and custom LLM integrations — can now call real Apex actions. That introduces three failure modes:

- **Prompt injection.** A hidden instruction in a record or email causes an agent to issue a call nobody asked for.
- **CRUD/FLS bypass.** Apex invocables run in system context by default, so an agent can read or mutate fields its user was never permissioned to touch.
- **Unaudited mutation.** DML fires in a loop with no throttle, no rollback boundary, and no real-time record of what happened.

AgentGuard SF is the missing enforcement layer: it wraps any `@InvocableMethod` with one line of code and treats every agent-issued call as untrusted input until it earns its way through five gates.

---

## Key Features

- **Five-gate enforcement chain** — SchemaValidator, AccessGate, RateLimiter, RollbackGuard, and AuditPublisher wrap every call; there's no bypass path.
- **Real running-user access control** — CRUD/FLS checks run `WITH USER_MODE` against the actual invoking user, never an elevated or system context.
- **Declarative policy configuration** — schema contracts, rate budgets, profile/permission-set scoping, and record ceilings live in `Guard_Policy__mdt`, tunable without an Apex deployment.
- **Transactional safety** — a Savepoint boundary plus a per-call record ceiling stop bulk-injection attacks from landing partial state.
- **Fail-closed by design** — any exception inside a gate is a BLOCK, never a silent ALLOW; every policy field defaults to its most restrictive safe value.
- **Real-time observability** — a Lightning dashboard (`guardAuditDashboard`) and the `sf agentguard` CLI plugin both watch the same `AgentGuard_Audit__e` stream live.
- **STRIDE-mapped threat coverage** — six threat categories, each tied to the specific gate that mitigates it. Full model: [Threat Model](docs/threat-model.md) · [Risk Register](docs/risk-register.md).
- **Zero dependencies** — no external callouts or npm/managed-package dependencies in the core enforcement path; MIT licensed.

---

## Architecture & How It Works

Every wrapped call passes through the same chain, in order, with no bypass path:

```
SchemaValidator → AccessGate → RateLimiter → RollbackGuard → AuditPublisher
```

A BLOCK, THROTTLE, or unhandled exception at any gate short-circuits the chain and still reaches AuditPublisher — a rejected call is never a silent failure. Policies are declarative: a `Guard_Policy__mdt` record per action defines the schema contract, rate budget, allowed profiles/permission sets, and record ceiling for that action, versioned and reviewed like any other metadata.

Full component diagram, request lifecycle, and ADR summaries: [Architecture](docs/architecture.md).

---

## Installation & Setup

| Prerequisite                 | Notes                                                              |
| ---------------------------- | ------------------------------------------------------------------ |
| Salesforce DX CLI (`sf`) v2+ | `npm install -g @salesforce/cli`                                   |
| Dev Hub org                  | Enterprise, Performance, or Unlimited Edition with Dev Hub enabled |
| API version 62.0+            | Set in `sfdx-project.json`                                         |

Deploy from source to a scratch org, or install the beta unlocked package (`0Hofj0000004KhhCAE`, 83% code coverage, not yet promoted for production) — full commands for both paths: **[Getting Started](docs/getting-started.md)**.

After deploying, create a Platform Cache partition named `AgentGuard` (Setup → Platform Cache → New Platform Cache Partition, ≥1 MB) so `RateLimiter` can enforce budgets. Without it, RateLimiter fails open and flags the audit event rather than blocking every agent action.

---

## Configuration & Usage Examples

Wrapping an existing `@InvocableMethod` requires one check before your business logic runs:

```apex
GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
```

That's it — the existing logic runs unchanged, now validated, access-checked, rate-limited, savepoint-wrapped, and audited. A `wrapAndExecute` variant handles rollback automatically if the business logic itself throws. Full code samples for both patterns: [Getting Started](docs/getting-started.md).

The policy referenced by name (`UpdateAccountTerritory` above) is a `Guard_Policy__mdt` record:

| Field                       | Description                                    | Example                  |
| --------------------------- | ---------------------------------------------- | ------------------------ |
| `DeveloperName`             | Matches the name passed to `AgentGuard.wrap()` | `UpdateAccountTerritory` |
| `IsActive__c`               | Master kill-switch; false blocks all calls     | `true`                   |
| `TargetSObjectType__c`      | SObject the action reads or writes             | `Account`                |
| `Operation__c`              | READ, CREATE, MODIFY, or REMOVE                | `MODIFY`                 |
| `SchemaContract__c`         | JSON schema for payload validation             | see below                |
| `MaxRecordsPerCall__c`      | Hard ceiling on DML rows per call              | `10`                     |
| `RateLimitPerMinute__c`     | Max calls per user per window                  | `30`                     |
| `RateLimitWindowSeconds__c` | Sliding window length (10–3600 s)              | `60`                     |

Full field reference, schema contract format, and worked examples: [Policy Configuration](docs/policy-configuration.md).

Monitor decisions from a terminal with the CLI plugin: `sf agentguard audit tail --target-org myorg`. Install and full command reference: [plugins/sf-agentguard/README.md](plugins/sf-agentguard/README.md).

---

## Testing & Code Coverage

AgentGuard SF ships 116 automated tests covering every gate's ALLOW and BLOCK paths — an ALLOW-only suite isn't acceptable for a security tool, so every gate has at least one negative test proving it correctly blocks a bad payload.

```bash
sf apex run test --target-org agentguard-dev --code-coverage --result-format human --wait 30
```

| Metric            | Value                      |
| ----------------- | -------------------------- |
| Tests             | 116/116 passing            |
| Org-wide coverage | 75% (meets deploy minimum) |
| Packaged coverage | 83%                        |

Coverage matrix mapping threats to automated tests: [Testing](docs/testing.md). Compliance evidence contributions (SOC 2 / GDPR / HIPAA): [Compliance Mapping](docs/compliance.md).

---

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, branch strategy, and review expectations. Every PR runs lint, PMD static analysis, scratch-org unit tests, and a coverage gate on `core/` classes.

If you are an AI coding agent, read [context/AGENTS.md](context/AGENTS.md) first — it defines the non-negotiable boundaries of this repository. Governance and decision-making process: [GOVERNANCE.md](/context/GOVERNANCE.md).

**Found a vulnerability?** Do not open a public issue — report privately via [GitHub Security Advisories](https://github.com/yashraghuvanshi/agentguard-sf/security/advisories/new). See [SECURITY.md](SECURITY.md) for response targets.

---

## License & Author

[MIT](LICENSE) — free for commercial and enterprise use.

Built and maintained by [Yash Raghuvanshi](https://github.com/yashraghuvanshi).
