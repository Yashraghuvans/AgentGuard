# FAQ

> **Status:** drafted — grows with real user questions after v0.8 soft launch.

## How is this different from the Einstein / Agentforce Trust Layer?

The Trust Layer protects what the LLM _sees_ (masking, grounding, retention at
the prompt boundary). AgentGuard SF is the gate that decides, in real time,
whether an agent-issued Apex action is allowed to touch your data _at all_. They
are complementary — see [LIMITS.md](../LIMITS.md).

## Is this a replacement for Agentforce Command Center?

No. Command Center reports what agents did, after the fact. AgentGuard enforces
before execution. AgentGuard's audit events can feed into or alongside it.

## Does it work with non-Agentforce agents (MCP servers, custom LLMs)?

Yes — it is framework-agnostic. Anything that can call your `@InvocableMethod`
goes through the same gates.

## What happens if AgentGuard itself has a bug?

It fails closed: an internal exception becomes a BLOCK, never an ALLOW
(ADR-002). Availability degrades before security does — deliberately.

## What does a wrapped call cost in governor limits?

Roughly 1–2 SOQL (policy lookup + describe cache miss), 0 DML in the gate path,
~2–6 ms CPU, 1 Platform Event publish per decision. Bulk calls batch checks so
overhead stays flat at 200 records. Full budget table ships with architecture
docs at v1.0.

## Why Custom Metadata Types instead of Custom Settings for policies?

Policy changes should ride the same review/CI pipeline as code. A Custom Setting
edited directly in production would bypass that entirely (ADR-003).
