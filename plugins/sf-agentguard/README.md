# @agentguard/sf-agentguard

Salesforce CLI plugin for monitoring AgentGuard audit events.

## Installation

```bash
sf plugins install @agentguard/sf-agentguard
```

## Commands

### `sf agentguard audit tail`

Stream AgentGuard audit events in real-time.

Subscribe to the `AgentGuard_Audit__e` Platform Event and display events as they occur. Events show decision (ALLOW/BLOCK/THROTTLED/ROLLBACK), action name, policy, gate, reason, and latency.

**Usage:**

```bash
# Stream all audit events
sf agentguard audit tail --target-org myorg

# Show only BLOCK decisions
sf agentguard audit tail --target-org myorg --decision BLOCK

# Show events from a specific policy
sf agentguard audit tail --target-org myorg --policy StrictPolicy

# Show only flagged events
sf agentguard audit tail --target-org myorg --flagged
```

**Flags:**

- `--target-org` (required): Target org for the command
- `--api-version`: API version to use
- `--decision, -d`: Filter by decision type (ALLOW, BLOCK, THROTTLED, ROLLBACK)
- `--policy, -p`: Filter by policy name
- `--flagged, -f`: Show only flagged events

Press `Ctrl+C` to stop streaming.

### `sf agentguard audit summary`

Collect and summarize AgentGuard audit events.

Listen to `AgentGuard_Audit__e` Platform Events for a specified duration and provide a statistical summary. Shows:

- Total event count
- Decision breakdown with percentages
- Top policies
- Gate activity
- Flagged event count
- Average latency

**Usage:**

```bash
# Collect events for 60 seconds (default)
sf agentguard audit summary --target-org myorg

# Collect for 5 minutes
sf agentguard audit summary --target-org myorg --duration 300

# Output as JSON for automation
sf agentguard audit summary --target-org myorg --json
```

**Flags:**

- `--target-org` (required): Target org for the command
- `--api-version`: API version to use
- `--duration, -d`: Duration in seconds to collect events (default: 60)
- `--json`: Output in JSON format

## Development

### Build

```bash
npm run build
```

### Link for local testing

```bash
sf plugins link
```

## Architecture

This plugin subscribes to the `AgentGuard_Audit__e` Platform Event using the Salesforce Streaming API. Events are published by AgentGuard outside the transaction rollback boundary (per ADR-001), ensuring a durable audit trail even for blocked operations.

The plugin does not store events persistently — it processes them in real-time. For long-term queryable history, implement a Platform Event trigger that persists events to a custom object (see `context/skills/agentguard-audit-monitor/SKILL.md`).

## Security Considerations

- The plugin displays `PayloadHash__c` (hash) but never reconstructs or logs raw payload data
- Audit events may contain sensitive information about what AI agents attempted
- Use appropriate org access controls when sharing terminal output or JSON summaries
- The `--flagged` filter helps focus on events requiring security review

## License

MIT
