# basic-invocable-wrap

> **Status:** ships at v0.1. Copy-paste starting point for wrapping an existing
> `@InvocableMethod` with `AgentGuard.wrap()`.

## Planned contents

- A sample `UpdateAccountTerritory` invocable action, wrapped
- A matching restrictive `Guard_Policy__mdt` policy record
- README walkthrough: deploy → invoke valid call → invoke malformed call →
  observe the BLOCK and its audit event

## Target experience

Deploys and runs on a fresh scratch org in under 5 minutes:

```bash
sf org create scratch -f config/project-scratch-def.json -a ag-demo
sf project deploy start -d examples/basic-invocable-wrap -o ag-demo
```
