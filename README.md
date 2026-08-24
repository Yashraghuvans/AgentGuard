# AgentGuard SF

[![CI](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml/badge.svg)](https://github.com/yashraghuvanshi/agentguard-sf/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> A lightweight, open-source Apex firewall between AI agents and your Salesforce data.

AI agents (Agentforce, MCP clients, custom LLM integrations) can now call your Apex
actions directly. AgentGuard SF wraps any `@InvocableMethod` with schema validation,
CRUD/FLS enforcement, rate limiting, transactional rollback, and real-time audit
logging — in one line, with zero external dependencies.

## Status: Pre-v0.1 (scaffolding)

The repository structure, governance docs, and CI pipeline are in place. Core gate
code lands with milestone [v0.1](CHANGELOG.md). See the
[Roadmap](#roadmap) below.

## Before / After

```apex
// Before — any payload shape, any user context, no audit trail
@InvocableMethod
public static List<Result> execute(List<Request> requests) {
    return TerritoryService.reassign(requests);
}

// After — validated, access-checked, rate-limited, rolled back on
// failure, and audited — before your logic ever runs
@InvocableMethod
public static List<Result> execute(List<Request> requests) {
    GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
    if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
    return TerritoryService.reassign(requests);
}
```

## Install (once v1.0 ships)

```bash
sf package install --package AgentGuardSF@1.0.0-1 -o myOrgAlias
```

## Why

Security and compliance teams routinely block AI-in-Apex initiatives because there's
no drop-in way to prove every agent-issued action is validated, access-checked,
throttled, and audited. AgentGuard SF is that missing enforcement layer — see the
[threat model](docs/threat-model.md) for exactly what it protects against.

## Roadmap

| Milestone | Scope | Target |
| --- | --- | --- |
| v0.1 — Core Gate | `AgentGuard.wrap()`, SchemaValidator, AccessGate, basic Platform Event audit log | Week 1–2 |
| v0.3 — Rate & Rollback | RateLimiter (Platform Cache), RollbackGuard (Savepoint) | Week 3–4 |
| v0.6 — Policy Metadata | `Guard_Policy__mdt` fully wired, declarative per-action config | Week 5–6 |
| v0.8 — Observability | LWC audit dashboard, SF CLI plugin for audit tailing | Week 7–8 |
| v1.0 — Public Launch | Docs site, 90%+ coverage, unlocked package, launch posts | Week 9–10 |

## Docs

Full documentation: https://yashraghuvanshi.github.io/agentguard-sf

Start with:
- [Getting Started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [Threat Model](docs/threat-model.md)
- [FAQ](docs/faq.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). If you're an AI coding agent, read
[AGENTS.md](AGENTS.md) first — it defines the hard boundaries of this repo.

## Security

See [SECURITY.md](SECURITY.md) for private vulnerability disclosure. Do not open
public issues for suspected vulnerabilities.

## License

MIT — see [LICENSE](LICENSE).
