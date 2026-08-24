<div align="center">

# AgentGuard SF

**A lightweight, open-source Apex security firewall between AI agents and your Salesforce data.**

Schema validation · CRUD/FLS enforcement · Rate limiting · Transactional rollback · Real-time audit

[![CI](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml)
[![CodeQL](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Overview](#overview) · [How It Works](#how-it-works) · [Quick Start](#quick-start) · [Threat Coverage](#threat-coverage) · [Docs](#documentation) · [Security](#security-policy)

</div>

---

## Status: Pre-v0.1

> This repository is in active development. Governance, CI, and tooling are in place;
> the core gate code lands with milestone **v0.1**. See [Roadmap](#roadmap).
> Until a tagged release exists, do not deploy to production orgs.

## Overview

Enterprises want AI agents — Agentforce, MCP-connected assistants, custom LLM
integrations — to invoke Apex actions that read and write real business data.
Three failure modes stop security teams from allowing it:

| Failure mode | What happens today |
| --- | --- |
| **Prompt injection** | An instruction hidden in a record, email, or knowledge article causes an agent to issue an action nobody asked for |
| **CRUD/FLS bypass** | Apex invocables run in system context by default — an agent reads or mutates fields its requesting user was never permissioned to touch |
| **Unaudited mutation** | A misbehaving agent fires DML in a loop with no throttle, no rollback boundary, and no real-time record of what it did |

Existing Salesforce controls operate at other layers: the Einstein Trust Layer
governs prompts, Agentforce Command Center reports outcomes after the fact.
Neither enforces anything at the moment an Apex action executes.

**AgentGuard SF is that missing enforcement layer.** It wraps any
`@InvocableMethod` with a single line of code and treats every agent-issued call
as untrusted input until it passes five gates. Zero external dependencies,
framework-agnostic, MIT licensed.

## How It Works

Every wrapped call passes through the same chain. There is no bypass path.

```
 Agent tool call
        │
        ▼
┌──────────────────┐   BLOCK   ┌──────────────────────────────────────┐
│  SchemaValidator │ ────────► │           AuditPublisher             │
└──────────────────┘           │                                      │
        │ allow                │  every decision — ALLOW, BLOCK, or   │
        ▼                      │  THROTTLED — publishes a real-time   │
┌──────────────────┐   BLOCK   │  AgentGuard_Audit__e Platform Event  │
│    AccessGate    │ ────────► │  with actor, payload hash, reason,   │
│ (WITH USER_MODE) │           │  and timestamp                       │
└──────────────────┘           └──────────────────────────────────────┘
        │ allow                           ▲
        ▼                                 │ THROTTLE
┌──────────────────┐                      │
│   RateLimiter    │ ─────────────────────┘
│ (sliding window) │
└──────────────────┘
        │ allow
        ▼
┌──────────────────┐
│  RollbackGuard   │   Savepoint boundary + max-records ceiling;
└──────────────────┘   any exception mid-execution rolls back atomically
        │
        ▼
  Business logic (unchanged)
```

Policies are declarative. A `Guard_Policy__mdt` record per action defines schema
contracts, rate budgets, allowed profiles/permission sets, and record ceilings —
tuned without an Apex deployment, versioned and reviewed like any other metadata.

### Design Guarantees

| Guarantee | Mechanism |
| --- | --- |
| **Fail closed** | Any exception inside a gate is a BLOCK, never an ALLOW |
| **Restrictive by default** | Every policy field defaults to its most restrictive safe value; nothing is permitted unless explicitly configured |
| **Running-user context only** | Access checks run `WITH USER_MODE` against the real user — never an elevated or claimed context |
| **Audit survives rollback** | Decisions publish as Platform Events, outside the transaction's rollback boundary |
| **One-line integration** | "Integrated correctly" and "integrated at all" are the same thing — one facade, per-gate toggles via policy |

## Quick Start

Once v0.1 tags:

```bash
# Install into any scratch org, Developer Edition, or Enterprise org
sf package install --package AgentGuardSF@<version> -o myOrgAlias

# Deploy the example policy and wrapped action
sf project deploy start -d examples/basic-invocable-wrap
```

Wrap an existing action — no refactor of surrounding business logic required:

```apex
@InvocableMethod(label='Update Account Territory')
public static List<Result> execute(List<Request> requests) {

    GuardResult check = AgentGuard.wrap(
        'UpdateAccountTerritory',   // policy name -> Guard_Policy__mdt
        JSON.serialize(requests)    // raw AI-originated payload
    );

    if (!check.isAllowed) {
        throw new AgentGuard.BlockedException(check.reason);
    }

    // Existing logic runs unchanged — now validated, access-checked,
    // throttled, inside a Savepoint boundary, and audited.
    return TerritoryService.reassign(requests);
}
```

Full walkthrough: [Getting Started](docs/getting-started.md).

## Threat Coverage

| STRIDE category | Mitigating component |
| --- | --- |
| Spoofing — agent claims a higher-privileged context | `AccessGate` evaluates against the real running-user context only |
| Tampering — injected payload reshaped into bulk/out-of-contract mutation | `SchemaValidator` rejects payloads violating the declared contract |
| Repudiation — destructive call with no record | `AuditPublisher` logs every decision with actor, payload hash, timestamp |
| Information disclosure — fields the user cannot see | `AccessGate` strips/blocks inaccessible fields on read paths |
| Denial of service — flooded actions exhausting limits | `RateLimiter` sliding-window per-agent/per-action budgets |
| Elevation of privilege — partial bulk mutations leave inconsistent state | `RollbackGuard` Savepoint boundary and record ceiling |

Full model, explicit non-goals, and the maintained risk register:
[threat-model.md](docs/threat-model.md) · [risk-register.md](docs/risk-register.md).

### What AgentGuard Does NOT Do

Honest scope boundaries ([LIMITS.md](LIMITS.md)):

- **Not a prompt-level control.** It does not mask data sent to an LLM — pair it
  with the Einstein Trust Layer at the prompt boundary.
- **Not a scanner.** It governs only calls that opt in via `AgentGuard.wrap()`.
- **No semantic injection detection.** Enforcement is structural, not a content classifier.
- **Not durable rate-limit state.** Platform Cache counters can reset on eviction.
- **No cross-org policy sync in v1.** Policies deploy per-org like any metadata.

## Documentation

| Document | Contents |
| --- | --- |
| [Getting Started](docs/getting-started.md) | Install, first wrap, first blocked call |
| [Architecture](docs/architecture.md) | Component diagram, request lifecycle, ADR summaries |
| [Policy Configuration](docs/policy-configuration.md) | Full `Guard_Policy__mdt` field reference |
| [API Reference](docs/api-reference.md) | Public method signatures |
| [Threat Model](docs/threat-model.md) | STRIDE analysis mapped to components |
| [Risk Register](docs/risk-register.md) | Known limitations and mitigations |
| [Testing](docs/testing.md) | Coverage matrix mapping threats to automated tests |
| [Compliance Mapping](docs/compliance.md) | SOC 2 / GDPR / HIPAA evidence contributions |

A hosted documentation site (Docusaurus on GitHub Pages) ships at v1.0.

## Roadmap

| Milestone | Scope | Target |
| --- | --- | --- |
| v0.1 — Core Gate | `wrap()` facade, SchemaValidator, AccessGate, audit event | Weeks 1–2 |
| v0.3 — Rate & Rollback | RateLimiter (Platform Cache), RollbackGuard (Savepoint) | Weeks 3–4 |
| v0.6 — Policy Metadata | Declarative `Guard_Policy__mdt` wiring | Weeks 5–6 |
| v0.8 — Observability | LWC audit dashboard, SF CLI audit-tail plugin | Weeks 7–8 |
| v1.0 — Public Launch | Docs site, unlocked package, ≥90% core coverage | Weeks 9–10 |

Detailed changelog: [CHANGELOG.md](CHANGELOG.md).

## Security Policy

AgentGuard SF is a security tool; vulnerability reports are treated as the
highest-priority work in this repository.

**Do not open public issues for suspected vulnerabilities.** Report privately
via [GitHub Security Advisories](https://github.com/yashraghuvanshi/agentguard-sf/security/advisories/new).
Acknowledgement within 72 hours; triage within 7 days. Full process and response
targets: [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
branch strategy, and review expectations. Every PR runs lint, PMD static
analysis, scratch-org unit tests, and a 90% coverage gate on `core/` classes.

If you are an AI coding agent, read [AGENTS.md](AGENTS.md) first — it defines
the non-negotiable boundaries of this repository.

Governance and decision-making process: [GOVERNANCE.md](GOVERNANCE.md).

## License

[MIT](LICENSE) — free for commercial and enterprise use.
