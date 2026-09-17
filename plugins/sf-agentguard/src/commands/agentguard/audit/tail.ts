import { SfCommand, Flags } from '@salesforce/sf-plugins-core';
import { Messages, Connection } from '@salesforce/core';
import chalk from 'chalk';

Messages.importMessagesDirectoryFromMetaUrl(import.meta.url);
const messages = Messages.loadMessages('@agentguard/sf-agentguard', 'agentguard.audit.tail');

export default class AuditTail extends SfCommand<void> {
  public static readonly summary = messages.getMessage('summary');
  public static readonly description = messages.getMessage('description');
  public static readonly examples = messages.getMessages('examples');

  public static readonly flags = {
    'target-org': Flags.requiredOrg(),
    'api-version': Flags.orgApiVersion(),
    decision: Flags.string({
      char: 'd',
      summary: 'Filter by decision type',
      description: 'Only show events matching this decision (ALLOW, BLOCK, THROTTLED, ROLLBACK)',
      options: ['ALLOW', 'BLOCK', 'THROTTLED', 'ROLLBACK'],
    }),
    policy: Flags.string({
      char: 'p',
      summary: 'Filter by policy name',
      description: 'Only show events from this policy',
    }),
    flagged: Flags.boolean({
      char: 'f',
      summary: 'Show only flagged events',
      description: 'Filter to events where Flagged__c is true',
      default: false,
    }),
  };

  public async run(): Promise<void> {
    const { flags } = await this.parse(AuditTail);
    const conn = flags['target-org'].getConnection(flags['api-version']);

    this.log(chalk.cyan('🔒 AgentGuard Audit Tail'));
    this.log(chalk.gray(`Streaming from: ${flags['target-org'].getUsername()}`));
    this.log(chalk.gray('Press Ctrl+C to stop\n'));

    this.guardAgainstTransportRejections();
    await this.streamEvents(conn, flags);
  }

  /**
   * jsforce's CometD transport (faye) can reject internal retry/advice
   * promises with no reason during normal long-poll cycling — Node treats
   * an unhandled rejection as fatal by default, which would otherwise kill
   * a long-running tail command over a routine transport hiccup. Log once
   * and keep listening; faye reconnects on its own.
   */
  private guardAgainstTransportRejections(): void {
    let warned = false;
    process.on('unhandledRejection', () => {
      if (!warned) {
        warned = true;
        this.warn('Streaming transport reported a transient error; still listening (Ctrl+C to stop).');
      }
    });
  }

  private async streamEvents(
    conn: Connection,
    flags: { decision?: string; policy?: string; flagged: boolean }
  ): Promise<void> {
    const channel = '/event/AgentGuard_Audit__e';

    // Subscribe to Platform Event
    try {
      await conn.streaming.topic(channel).subscribe((message: any) => {
        const event = message.payload;

        // Apply filters
        if (flags.decision && event.Decision__c !== flags.decision) {
          return;
        }
        if (flags.policy && event.PolicyName__c !== flags.policy) {
          return;
        }
        if (flags.flagged && !event.Flagged__c) {
          return;
        }

        this.printEvent(event);
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.error(`Failed to subscribe to ${channel}: ${message}`);
    }

    // Keep the process alive
    await new Promise(() => {
      // Intentionally never resolves - runs until Ctrl+C
    });
  }

  private printEvent(event: any): void {
    const timestamp = new Date().toISOString();
    const decision = event.Decision__c || 'UNKNOWN';
    const action = event.ActionName__c || 'N/A';
    const policy = event.PolicyName__c || 'N/A';
    const gate = event.GateName__c || 'N/A';
    const reason = event.Reason__c || '';
    const latency = event.LatencyMs__c || 0;
    const flagged = event.Flagged__c ? chalk.yellow(' [FLAGGED]') : '';

    // Color-code decisions
    let decisionColor;
    switch (decision) {
      case 'ALLOW':
        decisionColor = chalk.green;
        break;
      case 'BLOCK':
        decisionColor = chalk.red;
        break;
      case 'THROTTLED':
        decisionColor = chalk.yellow;
        break;
      case 'ROLLBACK':
        decisionColor = chalk.magenta;
        break;
      default:
        decisionColor = chalk.gray;
    }

    this.log(`${chalk.gray(timestamp)} ${decisionColor(decision.padEnd(10))} ${action}`);
    this.log(`  ${chalk.dim('Policy:')} ${policy} ${chalk.dim('Gate:')} ${gate}`);
    if (reason) {
      this.log(`  ${chalk.dim('Reason:')} ${reason}`);
    }
    this.log(`  ${chalk.dim('Latency:')} ${latency}ms${flagged}\n`);
  }
}
