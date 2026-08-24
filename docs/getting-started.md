# Getting Started

> **Status:** drafted — full content lands with v0.1 (core gate) and is finalized
> at v1.0. This page follows the blueprint's 5-minute quickstart contract.

## Install

```bash
sf package install --package AgentGuardSF@<version> -o myOrgAlias
```

## Deploy the example policy

```bash
sf project deploy start -d examples/basic-invocable-wrap
```

## Wrap your first action

```apex
@InvocableMethod(label='Update Account Territory')
public static List<Result> execute(List<Request> requests) {
    GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
    if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
    return TerritoryService.reassign(requests);
}
```

## Watch your first blocked call

```bash
sf agentguard audit tail   # ships at v0.8
```

Planned sections: prerequisites, scratch-org walkthrough, first ALLOW, first
BLOCK (with the audit event it produces), troubleshooting.
