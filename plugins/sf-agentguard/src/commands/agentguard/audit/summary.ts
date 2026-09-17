import { SfCommand, Flags } from '@salesforce/sf-plugins-core';
import { Messages, Connection } from '@salesforce/core';
import chalk from 'chalk';

Messages.importMessagesDirectoryFromMetaUrl(import.meta.url);
const messages = Messages.loadMessages('@agentguard/sf-agentguard', 'agentguard.audit.summary');

interface EventSummary {
  decisionCounts: Record<string, number>;
  policyCounts: Record<string, number>;
  gateCounts: Record<string, number>;
  flaggedCount: number;
  totalEvents: number;
  avgLatency: number;
  totalLatency: number;
}

export default class AuditSummary extends SfCommand<EventSummary> {
  public static readonly summary = messages.getMessage('summary');
  public static readonly description = messages.getMessage('description');
  public static readonly examples = messages.getMessages('examples');

  public static readonly flags = {
    'target-org': Flags.requiredOrg(),
    'api-version': Flags.orgApiVersion(),
    duration: Flags.integer({
      char: 'd',
      summary: 'Duration in seconds to collect events',
      description: 'How long to listen for events before summarizing (default: 60 seconds)',
      default: 60,
    }),
    json: Flags.boolean({
      summary: 'Output in JSON format',
      description: 'Format output as JSON',
    }),
  };

  public async run(): Promise<EventSummary> {
    const { flags } = await this.parse(AuditSummary);
    const conn = flags['target-org'].getConnection(flags['api-version']);

    if (!flags.json) {
      this.log(chalk.cyan('🔒 AgentGuard Audit Summary'));
      this.log(chalk.gray(`Collecting events for ${flags.duration} seconds...\n`));
    }

    this.guardAgainstTransportRejections();
    const summary = await this.collectEventSummary(conn, flags.duration);

    if (flags.json) {
      return summary;
    }

    this.printSummary(summary);
    return summary;
  }

  private async collectEventSummary(conn: Connection, duration: number): Promise<EventSummary> {
    const channel = '/event/AgentGuard_Audit__e';

    const summary: EventSummary = {
      decisionCounts: {},
      policyCounts: {},
      gateCounts: {},
      flaggedCount: 0,
      totalEvents: 0,
      avgLatency: 0,
      totalLatency: 0,
    };

    // Subscribe to Platform Event
    try {
      await conn.streaming.topic(channel).subscribe((message: any) => {
        this.handleEvent(summary, message.payload);
      });
    } catch (err) {
      const errMessage = err instanceof Error ? err.message : String(err);
      this.error(`Failed to subscribe to ${channel}: ${errMessage}`);
    }

    // Wait for specified duration
    await new Promise((resolve) => setTimeout(resolve, duration * 1000));

    // Calculate average latency
    if (summary.totalEvents > 0) {
      summary.avgLatency = Math.round(summary.totalLatency / summary.totalEvents);
    }

    return summary;
  }

  /**
   * jsforce's CometD transport (faye) can reject internal retry/advice
   * promises with no reason during normal long-poll cycling — Node treats
   * an unhandled rejection as fatal by default, which would otherwise kill
   * a collection window over a routine transport hiccup. Log once and keep
   * listening; faye reconnects on its own.
   */
  private guardAgainstTransportRejections(): void {
    let warned = false;
    process.on('unhandledRejection', () => {
      if (!warned) {
        warned = true;
        this.warn('Streaming transport reported a transient error; continuing to collect.');
      }
    });
  }

  private handleEvent(summary: EventSummary, event: any): void {
    summary.totalEvents++;

    // Track decision counts
    const decision = event.Decision__c || 'UNKNOWN';
    summary.decisionCounts[decision] = (summary.decisionCounts[decision] || 0) + 1;

    // Track policy counts
    const policy = event.PolicyName__c || 'UNKNOWN';
    summary.policyCounts[policy] = (summary.policyCounts[policy] || 0) + 1;

    // Track gate counts
    const gate = event.GateName__c || 'UNKNOWN';
    summary.gateCounts[gate] = (summary.gateCounts[gate] || 0) + 1;

    // Track flagged events
    if (event.Flagged__c) {
      summary.flaggedCount++;
    }

    // Track latency
    const latency = event.LatencyMs__c || 0;
    summary.totalLatency += latency;
  }

  private printSummary(summary: EventSummary): void {
    this.log(chalk.bold('\n📊 Summary Statistics\n'));
    this.log(`Total Events: ${chalk.cyan(summary.totalEvents.toString())}`);
    this.log(`Flagged Events: ${chalk.yellow(summary.flaggedCount.toString())}`);
    this.log(`Average Latency: ${chalk.cyan(summary.avgLatency.toString())}ms\n`);

    // Decision breakdown
    this.log(chalk.bold('Decisions:\n'));
    const decisions = ['ALLOW', 'BLOCK', 'THROTTLED', 'ROLLBACK'];
    for (const decision of decisions) {
      const count = summary.decisionCounts[decision] || 0;
      const percentage =
        summary.totalEvents > 0 ? ((count / summary.totalEvents) * 100).toFixed(1) : '0.0';
      const color = this.getDecisionColor(decision);
      this.log(`  ${color(decision.padEnd(10))} ${count.toString().padStart(5)} (${percentage}%)`);
    }

    // Policy breakdown
    if (Object.keys(summary.policyCounts).length > 0) {
      this.log(chalk.bold('\nTop Policies:\n'));
      const sortedPolicies = Object.entries(summary.policyCounts)
        .sort(([, a], [, b]) => b - a)
        .slice(0, 5);

      for (const [policy, count] of sortedPolicies) {
        this.log(`  ${policy.padEnd(30)} ${count.toString().padStart(5)}`);
      }
    }

    // Gate breakdown
    if (Object.keys(summary.gateCounts).length > 0) {
      this.log(chalk.bold('\nGate Activity:\n'));
      const sortedGates = Object.entries(summary.gateCounts).sort(([, a], [, b]) => b - a);

      for (const [gate, count] of sortedGates) {
        this.log(`  ${gate.padEnd(30)} ${count.toString().padStart(5)}`);
      }
    }

    this.log('');
  }

  private getDecisionColor(decision: string): (text: string) => string {
    switch (decision) {
      case 'ALLOW':
        return chalk.green;
      case 'BLOCK':
        return chalk.red;
      case 'THROTTLED':
        return chalk.yellow;
      case 'ROLLBACK':
        return chalk.magenta;
      default:
        return chalk.gray;
    }
  }
}
