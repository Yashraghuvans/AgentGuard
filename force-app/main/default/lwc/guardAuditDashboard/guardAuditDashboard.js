import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const CHANNEL_NAME = '/event/AgentGuard_Audit__e';
const MAX_RECENT_EVENTS = 50;

export default class GuardAuditDashboard extends LightningElement {
  @track decisionCounts = {
    ALLOW: 0,
    BLOCK: 0,
    THROTTLED: 0,
    ROLLBACK: 0
  };

  @track recentEvents = [];
  @track isConnected = false;
  @track error;

  subscription = null;

  connectedCallback() {
    this.registerErrorListener();
    this.handleSubscribe();
  }

  disconnectedCallback() {
    this.handleUnsubscribe();
  }

  registerErrorListener() {
    onError((error) => {
      console.error('EMP API Error:', JSON.stringify(error));
      this.error = 'Streaming API error: ' + (error?.message || 'Unknown error');
    });
  }

  handleSubscribe() {
    const messageCallback = (response) => {
      try {
        const event = response?.data?.payload;
        if (event) {
          this.processAuditEvent(event);
        }
      } catch (err) {
        console.error('Error processing audit event:', err);
      }
    };

    subscribe(CHANNEL_NAME, -1, messageCallback)
      .then((response) => {
        this.subscription = response;
        this.isConnected = true;
        this.error = null;
        console.log('Subscribed to AgentGuard audit events:', response.channel);
      })
      .catch((error) => {
        console.error('Subscription error:', JSON.stringify(error));
        this.error = 'Failed to subscribe: ' + (error?.message || 'Unknown error');
      });
  }

  handleUnsubscribe() {
    if (this.subscription) {
      unsubscribe(this.subscription)
        .then(() => {
          console.log('Unsubscribed from AgentGuard audit events');
          this.subscription = null;
          this.isConnected = false;
        })
        .catch((error) => {
          console.error('Unsubscribe error:', JSON.stringify(error));
        });
    }
  }

  processAuditEvent(event) {
    // Update decision counts
    const decision = event.Decision__c;
    if (decision && this.decisionCounts.hasOwnProperty(decision)) {
      this.decisionCounts = {
        ...this.decisionCounts,
        [decision]: this.decisionCounts[decision] + 1
      };
    }

    // Add to recent events feed (newest first)
    const recentEvent = {
      id: Date.now() + '_' + Math.random(), // Unique key for list rendering
      timestamp: new Date().toISOString(),
      actionName: event.ActionName__c || 'N/A',
      policyName: event.PolicyName__c || 'N/A',
      gateName: event.GateName__c || 'N/A',
      decision: decision || 'UNKNOWN',
      decisionClass: this.getDecisionClass(decision),
      reason: event.Reason__c || '',
      flagged: event.Flagged__c === true,
      latencyMs: event.LatencyMs__c || 0,
      payloadHash: event.PayloadHash__c || 'N/A'
    };

    this.recentEvents = [recentEvent, ...this.recentEvents].slice(0, MAX_RECENT_EVENTS);
  }

  get statusMessage() {
    if (this.error) {
      return this.error;
    }
    return this.isConnected ? 'Connected to audit stream' : 'Connecting...';
  }

  get statusClass() {
    if (this.error) {
      return 'slds-text-color_error';
    }
    return this.isConnected ? 'slds-text-color_success' : 'slds-text-color_weak';
  }

  get hasEvents() {
    return this.recentEvents.length > 0;
  }

  get statusIcon() {
    if (this.error) {
      return 'utility:error';
    }
    return this.isConnected ? 'utility:success' : 'utility:spinner';
  }

  getDecisionClass(decision) {
    switch (decision) {
      case 'ALLOW':
        return 'decision-allow';
      case 'BLOCK':
        return 'decision-block';
      case 'THROTTLED':
        return 'decision-throttled';
      case 'ROLLBACK':
        return 'decision-rollback';
      default:
        return '';
    }
  }
}
