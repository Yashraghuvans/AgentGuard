# agentforce-action-integration

> **Status:** ships at v0.6+. Shows an Agentforce action wired through
> AgentGuard with a declarative `Guard_Policy__mdt` policy — no Apex deployment
> needed to tune the policy afterward.

## Planned contents

- An Agentforce-configured action whose invocable method is AgentGuard-wrapped
- Policy record scoped to the `Agentforce Service Agent` profile
- Walkthrough: register the action in Agentforce, attempt a legitimate call and
  a prompt-injection-shaped bulk payload, inspect the resulting
  `AgentGuard_Audit__e` events
