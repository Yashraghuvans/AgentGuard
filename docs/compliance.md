# Compliance Framework Mapping

> **Status:** drafted — finalized at v1.0 with the docs site.

## Important Caveat

This mapping shows how AgentGuard's controls **contribute evidence toward** these
frameworks. It is **not a certification** and does not by itself make an org
compliant. Do not overclaim.

| Framework / Control | Requirement | How AgentGuard helps |
| --- | --- | --- |
| SOC 2 — CC6 (Logical Access) | Access restricted to authorized users/processes | `AccessGate` enforces CRUD/FLS per running user on every AI-originated call, not just human ones |
| SOC 2 — CC7 (System Monitoring) | Monitoring for anomalous/malicious activity | `RateLimiter` flags anomalous volume; every decision published as real-time queryable audit event |
| GDPR — Art. 5(2) (Accountability) | Demonstrate compliance with data-processing principles | `AuditPublisher` provides durable timestamped record of every data-mutating action an agent attempted, allowed or blocked |
| GDPR — Art. 25 (Data Protection by Design) | Data protection by default | Restrictive-by-default policy posture: nothing permitted unless explicitly configured |
| HIPAA — 164.312(b) (Audit Controls) | Mechanisms to record/examine activity in PHI systems | Every AI-driven touch of PHI-bearing objects through AgentGuard captured in the audit stream |
| HIPAA — 164.312(a)(1) (Access Control) | Technical access policies for persons/programs | `AccessGate` + `Guard_Policy__mdt` scoping restrict which agents/actions touch which fields |
