import { createElement } from 'lwc';
import GuardAuditDashboard from 'c/guardAuditDashboard';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

// Mock empApi
jest.mock(
  'lightning/empApi',
  () => {
    return {
      subscribe: jest.fn(),
      unsubscribe: jest.fn(),
      onError: jest.fn()
    };
  },
  { virtual: true }
);

describe('c-guard-audit-dashboard', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('subscribes to AgentGuard_Audit__e on connect', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    subscribe.mockResolvedValue({ channel: '/event/AgentGuard_Audit__e' });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      expect(subscribe).toHaveBeenCalledWith('/event/AgentGuard_Audit__e', -1, expect.any(Function));
      expect(onError).toHaveBeenCalled();
    });
  });

  it('unsubscribes on disconnect', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    const mockSubscription = { channel: '/event/AgentGuard_Audit__e' };
    subscribe.mockResolvedValue(mockSubscription);
    unsubscribe.mockResolvedValue();

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      document.body.removeChild(element);

      return Promise.resolve().then(() => {
        expect(unsubscribe).toHaveBeenCalledWith(mockSubscription);
      });
    });
  });

  it('displays initial decision counts as zero', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    subscribe.mockResolvedValue({ channel: '/event/AgentGuard_Audit__e' });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const statCards = element.shadowRoot.querySelectorAll('.stat-card');
      expect(statCards.length).toBe(4);

      // Check all counts are 0
      const statValues = element.shadowRoot.querySelectorAll('.stat-value');
      statValues.forEach((value) => {
        expect(value.textContent).toBe('0');
      });
    });
  });

  it('increments ALLOW count when receiving ALLOW event', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      // Simulate receiving an ALLOW event
      messageCallback({
        data: {
          payload: {
            ActionName__c: 'Account.query',
            Decision__c: 'ALLOW',
            PolicyName__c: 'StandardPolicy',
            GateName__c: 'AccessGate',
            Reason__c: 'CRUD allowed',
            LatencyMs__c: 12,
            PayloadHash__c: 'abc123',
            Flagged__c: false
          }
        }
      });

      return Promise.resolve().then(() => {
        const allowCard = element.shadowRoot.querySelector('.decision-allow .stat-value');
        expect(allowCard.textContent).toBe('1');
      });
    });
  });

  it('increments BLOCK count when receiving BLOCK event', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      messageCallback({
        data: {
          payload: {
            ActionName__c: 'Contact.delete',
            Decision__c: 'BLOCK',
            PolicyName__c: 'StrictPolicy',
            GateName__c: 'AccessGate',
            Reason__c: 'DELETE not allowed',
            LatencyMs__c: 8,
            PayloadHash__c: 'def456',
            Flagged__c: true
          }
        }
      });

      return Promise.resolve().then(() => {
        const blockCard = element.shadowRoot.querySelector('.decision-block .stat-value');
        expect(blockCard.textContent).toBe('1');
      });
    });
  });

  it('adds events to recent events feed', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      messageCallback({
        data: {
          payload: {
            ActionName__c: 'Lead.create',
            Decision__c: 'THROTTLED',
            PolicyName__c: 'RateLimitPolicy',
            GateName__c: 'RateLimiter',
            Reason__c: 'Rate limit exceeded',
            LatencyMs__c: 5,
            PayloadHash__c: 'ghi789',
            Flagged__c: false
          }
        }
      });

      return Promise.resolve().then(() => {
        const eventCards = element.shadowRoot.querySelectorAll('.event-card');
        expect(eventCards.length).toBe(1);

        const actionValue = element.shadowRoot.querySelector('.detail-value');
        expect(actionValue.textContent).toBe('Lead.create');
      });
    });
  });

  it('displays flagged badge for flagged events', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      messageCallback({
        data: {
          payload: {
            ActionName__c: 'Opportunity.update',
            Decision__c: 'ALLOW',
            PolicyName__c: 'MonitorPolicy',
            GateName__c: 'SchemaValidator',
            Reason__c: 'Schema valid but flagged for review',
            LatencyMs__c: 15,
            PayloadHash__c: 'jkl012',
            Flagged__c: true
          }
        }
      });

      return Promise.resolve().then(() => {
        const flaggedBadge = element.shadowRoot.querySelector('.flagged-badge');
        expect(flaggedBadge).toBeTruthy();
        expect(flaggedBadge.textContent).toContain('Flagged for Review');
      });
    });
  });

  it('limits recent events to MAX_RECENT_EVENTS', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      // Send 55 events (MAX is 50)
      for (let i = 0; i < 55; i++) {
        messageCallback({
          data: {
            payload: {
              ActionName__c: `Action${i}`,
              Decision__c: 'ALLOW',
              PolicyName__c: 'TestPolicy',
              GateName__c: 'TestGate',
              LatencyMs__c: 1,
              PayloadHash__c: `hash${i}`
            }
          }
        });
      }

      return Promise.resolve().then(() => {
        const eventCards = element.shadowRoot.querySelectorAll('.event-card');
        expect(eventCards.length).toBe(50);
      });
    });
  });

  it('handles missing event fields gracefully', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    let messageCallback;
    subscribe.mockImplementation((channel, replayId, callback) => {
      messageCallback = callback;
      return Promise.resolve({ channel });
    });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      // Send event with minimal fields
      messageCallback({
        data: {
          payload: {
            Decision__c: 'BLOCK'
          }
        }
      });

      return Promise.resolve().then(() => {
        const eventCards = element.shadowRoot.querySelectorAll('.event-card');
        expect(eventCards.length).toBe(1);

        // Should display N/A for missing fields
        const detailValues = element.shadowRoot.querySelectorAll('.detail-value');
        expect(detailValues[0].textContent).toBe('N/A'); // ActionName
      });
    });
  });

  it('displays connection status correctly', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    subscribe.mockResolvedValue({ channel: '/event/AgentGuard_Audit__e' });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const statusElement = element.shadowRoot.querySelector('.slds-text-color_success');
      expect(statusElement).toBeTruthy();
      expect(statusElement.textContent).toContain('Connected to audit stream');
    });
  });

  it('displays error message on subscription failure', () => {
    const element = createElement('c-guard-audit-dashboard', {
      is: GuardAuditDashboard
    });

    subscribe.mockRejectedValue({ message: 'Connection failed' });

    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const errorElement = element.shadowRoot.querySelector('.slds-text-color_error');
      expect(errorElement).toBeTruthy();
      expect(errorElement.textContent).toContain('Failed to subscribe');
    });
  });
});
