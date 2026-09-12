<div align="center">

# AgentGuard SF

**A lightweight, open-source Apex security firewall between AI agents and your Salesforce data.**

Schema validation · CRUD/FLS enforcement · Rate limiting · Transactional rollback · Real-time audit

[![CI](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml)
[![CodeQL](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Tests](https://img.shields.io/badge/tests-75%2F75%20passing-brightgreen)](docs/testing.md)

[Overview](#overview) · [How It Works](#how-it-works) · [Quick Start](#quick-start) · [Deployment](#deployment) · [Threat Coverage](#threat-coverage) · [Documentation](#documentation) · [Security](#security-policy)

</div>

---

## Overview

Enterprises want AI agents — Agentforce, MCP-connected assistants, custom LLM integrations — to invoke Apex actions that read and write real business data. Three failure modes stop security teams from allowing it:

| Failure mode           | What happens today                                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Prompt injection**   | An instruction hidden in a record, email, or knowledge article causes an agent to issue an action nobody asked for                      |
| **CRUD/FLS bypass**    | Apex invocables run in system context by default — an agent reads or mutates fields its requesting user was never permissioned to touch |
| **Unaudited mutation** | A misbehaving agent fires DML in a loop with no throttle, no rollback boundary, and no real-time record of what it did                  |

Existing Salesforce controls operate at other layers: the Einstein Trust Layer governs prompts, Agentforce Command Center reports outcomes after the fact. Neither enforces anything at the moment an Apex action executes.

**AgentGuard SF is that missing enforcement layer.** It wraps any `@InvocableMethod` with a single line of code and treats every agent-issued call as untrusted input until it passes five gates. Zero external dependencies, framework-agnostic, MIT licensed.

---

## How It Works

Every wrapped call passes through the same chain. There is no bypass path.

```
 Agent tool call
        |
        v
+------------------+   BLOCK   +--------------------------------------+
|  SchemaValidator | --------> |           AuditPublisher             |
+------------------+           |                                      |
        | allow                |  every decision — ALLOW, BLOCK, or   |
        v                      |  THROTTLED — publishes a real-time   |
+------------------+   BLOCK   |  AgentGuard_Audit__e Platform Event  |
|    AccessGate    | --------> |  with actor, payload hash, reason,   |
| (WITH USER_MODE) |           |  and timestamp                       |
+------------------+           +--------------------------------------+
        | allow                           ^
        v                                 | THROTTLE
+------------------+                      |
|   RateLimiter    | ---------------------+
| (sliding window) |
+------------------+
        | allow
        v
+------------------+
|  RollbackGuard   |   Savepoint boundary + max-records ceiling;
+------------------+   any exception mid-execution rolls back atomically
        |
        v
  Business logic (unchanged)
```

Policies are declarative. A `Guard_Policy__mdt` record per action defines schema contracts, rate budgets, allowed profiles/permission sets, and record ceilings — tuned without an Apex deployment, versioned and reviewed like any other metadata.

### Design Guarantees

| Guarantee                     | Mechanism                                                                                                         |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Fail closed**               | Any exception inside a gate is a BLOCK, never an ALLOW                                                            |
| **Restrictive by default**    | Every policy field defaults to its most restrictive safe value; nothing is permitted unless explicitly configured |
| **Running-user context only** | Access checks run `WITH USER_MODE` against the real user — never an elevated or claimed context                   |
| **Audit survives rollback**   | Decisions publish as Platform Events, outside the transaction's rollback boundary                                 |
| **One-line integration**      | "Integrated correctly" and "integrated at all" are the same thing — one facade, per-gate toggles via policy       |

---

## Quick Start

### Option 1: Deploy from Source

```bash
# Authenticate to your Dev Hub
sf org login web --set-default-dev-hub --alias devhub

# Create a scratch org
sf org create scratch --definition-file config/project-scratch-def.json --alias agentguard-dev --duration-days 30 --set-default

# Deploy all metadata
sf project deploy start --target-org agentguard-dev

# Run the full test suite (75 tests, should all pass)
sf apex run test --target-org agentguard-dev --code-coverage --result-format human --wait 30
```

### Option 2: Install Package (coming at v1.0)

```bash
sf package install --package AgentGuardSF@<version> -o myOrgAlias
```

---

## Integration

Wrapping an existing `@InvocableMethod` requires one check before your business logic runs:

```apex
@InvocableMethod(label='Update Account Territory')
public static List<Result> execute(List<Request> requests) {

    GuardResult check = AgentGuard.wrap(
        'UpdateAccountTerritory',   // matches Guard_Policy__mdt DeveloperName
        JSON.serialize(requests)    // raw AI-originated payload
    );

    if (!check.isAllowed) {
        throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
    }

    // Existing logic runs unchanged — validated, access-checked,
    // throttled, inside a Savepoint boundary, and audited.
    return TerritoryService.reassign(requests);
}
```

For automatic rollback on business logic exceptions:

```apex
GuardResult result = AgentGuard.wrapAndExecute(
    'UpdateAccountTerritory',
    JSON.serialize(requests),
    new MyCallback()
);

private class MyCallback implements RollbackGuard.GuardResultCallback {
    public GuardResult execute(GuardResult allow) {
        // your DML here — rolled back automatically if this throws
        return TerritoryService.reassign(requests);
    }
}
```

Full walkthrough: [Getting Started](docs/getting-started.md).

---

## Deployment

### Prerequisites

| Requirement                  | Notes                                                              |
| ---------------------------- | ------------------------------------------------------------------ |
| Salesforce DX CLI (`sf`) v2+ | `npm install -g @salesforce/cli`                                   |
| Dev Hub org                  | Enterprise, Performance, or Unlimited Edition with Dev Hub enabled |
| API version 62.0+            | Set in `sfdx-project.json`                                         |

### Platform Cache (Required for Rate Limiting)

After deploying, create the platform cache partition in your org:

1. Go to **Setup > Platform Cache**
2. Click **New Platform Cache Partition**
3. Set the name to **`AgentGuard`**
4. Allocate at least 1 MB of org cache
5. Save

Without this partition, `RateLimiter` operates in fail-open mode (logs a flagged audit event but allows the call).

### Configuring a Policy

Create a `Guard_Policy__mdt` record with:

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

Example schema contract:

```json
{
  "properties": {
    "AccountId": { "type": "string" },
    "Territory__c": { "type": "string" }
  },
  "required": ["AccountId"]
}
```

---

## Threat Coverage

| STRIDE category                                                          | Mitigating component                                                     |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| Spoofing — agent claims a higher-privileged context                      | `AccessGate` evaluates against the real running-user context only        |
| Tampering — injected payload reshaped into bulk/out-of-contract mutation | `SchemaValidator` rejects payloads violating the declared contract       |
| Repudiation — destructive call with no record                            | `AuditPublisher` logs every decision with actor, payload hash, timestamp |
| Information disclosure — fields the user cannot see                      | `AccessGate` strips/blocks inaccessible fields on read paths             |
| Denial of service — flooded actions exhausting limits                    | `RateLimiter` sliding-window per-agent/per-action budgets                |
| Elevation of privilege — partial bulk mutations leave inconsistent state | `RollbackGuard` Savepoint boundary and record ceiling                    |

Full model, explicit non-goals, and the maintained risk register: [threat-model.md](docs/threat-model.md) · [risk-register.md](docs/risk-register.md).

### What AgentGuard Does Not Do

Honest scope boundaries ([LIMITS.md](/context/LIMITS.md)):

- **Not a prompt-level control.** It does not mask data sent to an LLM — pair it with the Einstein Trust Layer at the prompt boundary.
- **Not a scanner.** It governs only calls that opt in via `AgentGuard.wrap()`.
- **No semantic injection detection.** Enforcement is structural, not a content classifier.
- **Not durable rate-limit state.** Platform Cache counters can reset on eviction; pair with Shield Event Monitoring for a durable audit trail.
- **No cross-org policy sync in v1.** Policies deploy per-org like any metadata.

---

## Documentation

| Document                                             | Contents                                            |
| ---------------------------------------------------- | --------------------------------------------------- |
| [Getting Started](docs/getting-started.md)           | Install, first wrap, first blocked call             |
| [Architecture](docs/architecture.md)                 | Component diagram, request lifecycle, ADR summaries |
| [Policy Configuration](docs/policy-configuration.md) | Full `Guard_Policy__mdt` field reference            |
| [API Reference](docs/api-reference.md)               | Public method signatures                            |
| [Threat Model](docs/threat-model.md)                 | STRIDE analysis mapped to components                |
| [Risk Register](docs/risk-register.md)               | Known limitations and mitigations                   |
| [Testing](docs/testing.md)                           | Coverage matrix mapping threats to automated tests  |
| [Compliance Mapping](docs/compliance.md)             | SOC 2 / GDPR / HIPAA evidence contributions         |

---

## Project Structure

```
force-app/main/default/
  classes/
    core/               # Gate chain: AgentGuard, SchemaValidator, AccessGate,
    |                   # RateLimiter, RollbackGuard, AuditPublisher, PolicyRegistry
    models/             # Value types: GuardResult, GuardPolicy
    tests/              # 75 tests, 100% pass rate
  objects/
    AgentGuard_Audit__e/   # Platform Event — one per gate decision
    Guard_Policy__mdt/     # Custom Metadata Type — policy per action
examples/
  basic-invocable-wrap/    # Minimal working integration
  agentforce-action-integration/  # Agentforce-specific pattern
docs/                   # Extended documentation
context/                # Governance, rules, and contribution guidelines
```

---

## Roadmap

| Milestone              | Scope                                                  | Status        |
| ---------------------- | ------------------------------------------------------ | ------------- |
| v0.1 — Core Gate       | `wrap()` facade, all five gates, audit event, 75 tests | **Complete**  |
| v0.3 — Rate & Rollback | Platform Cache partition, Savepoint recovery flows     | In gate chain |
| v0.6 — Policy Metadata | Live `Guard_Policy__mdt` wiring, seed data             | Partial       |
| v0.8 — Observability   | LWC audit dashboard, CLI audit-tail plugin             | Planned       |
| v1.0 — Public Launch   | Docs site, unlocked package, 90% core coverage gate    | Planned       |

Detailed changelog: [CHANGELOG.md](CHANGELOG.md).

---

## Security Policy

AgentGuard SF is a security tool; vulnerability reports are treated as the highest-priority work in this repository.

**Do not open public issues for suspected vulnerabilities.** Report privately via [GitHub Security Advisories](https://github.com/yashraghuvanshi/agentguard-sf/security/advisories/new). Acknowledgement within 72 hours; triage within 7 days. Full process and response targets: [SECURITY.md](SECURITY.md).

---

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, branch strategy, and review expectations. Every PR runs lint, PMD static analysis, scratch-org unit tests, and a coverage gate on `core/` classes.

If you are an AI coding agent, read [context/AGENTS.md](context/AGENTS.md) first — it defines the non-negotiable boundaries of this repository.

Governance and decision-making process: [GOVERNANCE.md](/context/GOVERNANCE.md).

---

## License

[MIT](LICENSE) — free for commercial and enterprise use.
