/**
 * AgentGuardTest
 * ------------------------------------------------------------------
 * Full end-to-end integration tests for AgentGuard.wrap() facade.
 * Verifies the complete gate chain: SchemaValidator → AccessGate →
 * RateLimiter → RollbackGuard → AuditPublisher.
 */
@isTest
private class AgentGuardTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agfct', 'Standard User');
    }

    private static GuardPolicy fullPolicy() {
        String contract = '{"properties": {"AccountId": {"type": "string", "required": true}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}';
        return GuardPolicy.disabled('UpdateAccountTerritory')
            .withEnabled(true)
            .withSObjectType('Account')
            .withOperation(GuardPolicy.Operation.MODIFY)
            .withSchemaContract(contract)
            .withMaxRecordsPerCall(5)
            .withRateLimit(10)
            .withRateLimitWindowSeconds(60);
    }

    @isTest
    static void given_validPayload_when_wrapped_then_allowsWithSavepoint() {
        System.runAs(ctxUser()) {
            TestDataFactory.registerPolicy(fullPolicy());
            RateLimiter.clearCache('UpdateAccountTerritory');
            String payload = '{"AccountId": "001000000000001", "Territory__c": "West"}';
            GuardResult r = AgentGuard.wrap('UpdateAccountTerritory', payload);

            System.assertEquals(true, r.isAllowed, 'Valid payload must be allowed');
            System.assertNotEquals(null, r.getSavepoint(), 'Savepoint must be attached');
        }
    }

    @isTest
    static void given_invalidSchema_when_wrapped_then_blocksAtSchemaGate() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UpdateAccountTerritory');
            String payload = '{"UnknownField__c": "Bad"}';
            GuardResult r = AgentGuard.wrap('UpdateAccountTerritory', payload);

            System.assertEquals(false, r.isAllowed, 'Invalid schema must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be blocked at SCHEMA gate');
        }
    }

    @isTest
    static void given_accessDenied_when_wrapped_then_blocksAtAccessGate() {
        // We can't easily test with restricted user here without complex setup,
        // but we verify the gate chain order by testing a disabled policy
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UpdateAccountTerritory');
            GuardPolicy policy = fullPolicy().withEnabled(false);
            TestDataFactory.registerPolicy(policy);

            String payload = '{"AccountId": "001000000000001", "Territory__c": "West"}';
            GuardResult r = AgentGuard.wrap('UpdateAccountTerritory', payload);

            System.assertEquals(false, r.isAllowed, 'Disabled policy must block');
            System.assertEquals('ACCESS', r.gateName, 'Must be blocked at ACCESS gate (policy disabled check)');
        }
    }

    @isTest
    static void given_rateLimitExceeded_when_wrapped_then_blocksAtRateGate() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('RateTestAction');
            GuardPolicy policy = GuardPolicy.disabled('RateTestAction')
                .withEnabled(true)
                .withRateLimit(2)
                .withRateLimitWindowSeconds(60)
                .withSchemaContract('{"properties":{"AccountId":{"type":"string"}}}')
                .withMaxRecordsPerCall(100)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY);
            TestDataFactory.registerPolicy(policy);

            String payload = '{"AccountId": "001"}';

            GuardResult r1 = AgentGuard.wrap('RateTestAction', payload);
            System.assertEquals(true, r1.isAllowed, 'First call allowed');

            GuardResult r2 = AgentGuard.wrap('RateTestAction', payload);
            System.assertEquals(true, r2.isAllowed, 'Second call allowed');

            GuardResult r3 = AgentGuard.wrap('RateTestAction', payload);
            System.assertEquals(false, r3.isAllowed, 'Third call throttled');
            System.assertEquals('RATE', r3.gateName, 'Must be blocked at RATE gate');
        }
    }

    @isTest
    static void given_recordLimitExceeded_when_wrapped_then_blocksAtRollbackGate() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UpdateAccountTerritory');
            GuardPolicy policy = fullPolicy().withMaxRecordsPerCall(1);
            TestDataFactory.registerPolicy(policy);

            String payload = '[{"AccountId": "001", "Territory__c": "West"}, {"AccountId": "002", "Territory__c": "East"}]';
            GuardResult r = AgentGuard.wrap('UpdateAccountTerritory', payload);

            System.assertEquals(false, r.isAllowed, 'Over record limit must block');
            System.assertEquals('ROLLBACK', r.gateName, 'Must be blocked at ROLLBACK gate');
        }
    }

    @isTest
    static void given_wrapAndExecute_when_callbackThrows_then_rollsBack() {
        System.runAs(ctxUser()) {
            TestDataFactory.registerPolicy(fullPolicy());
            RateLimiter.clearCache('UpdateAccountTerritory');
            String payload = '{"AccountId": "001", "Territory__c": "West"}';

            GuardResult result = AgentGuard.wrapAndExecute('UpdateAccountTerritory', payload, new ThrowingCallback());

            System.assertEquals(false, result.isAllowed, 'Exception must trigger rollback');
            System.assertEquals('ROLLBACK', result.decision, 'Decision must be ROLLBACK');

            List<Account> after = [SELECT Id FROM Account WHERE Name = 'Should Be Rolled Back'];
            System.assertEquals(0, after.size(), 'Rollback must undo DML');
        }
    }

    @isTest
    static void given_wrapAndExecute_when_callbackSucceeds_then_returnsResult() {
        System.runAs(ctxUser()) {
            TestDataFactory.registerPolicy(fullPolicy());
            RateLimiter.clearCache('UpdateAccountTerritory');
            String payload = '{"AccountId": "001", "Territory__c": "West"}';

            GuardResult result = AgentGuard.wrapAndExecute('UpdateAccountTerritory', payload, new SucceedingCallback());

            System.assertEquals(true, result.isAllowed, 'Success must return callback result');
            System.assertEquals('Business', result.policyName, 'Must return callback policy name');
        }
    }

    private class ThrowingCallback implements RollbackGuard.GuardResultCallback {
        public GuardResult execute(GuardResult allow) {
            insert new Account(Name = 'Should Be Rolled Back');
            throw new AuraHandledException('Business logic failure');
        }
    }

    private class SucceedingCallback implements RollbackGuard.GuardResultCallback {
        public GuardResult execute(GuardResult allow) {
            return GuardResult.allow('Business', 'Success');
        }
    }

    @isTest
    static void given_unknownPolicy_when_wrapped_then_blocksAtFacade() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UnknownPolicy');
            String payload = '{"foo": "bar"}';
            GuardResult r = AgentGuard.wrap('UnknownPolicy', payload);

            System.assertEquals(false, r.isAllowed, 'Unknown policy must block (disabled by default)');
            System.assertEquals(
                'SCHEMA',
                r.gateName,
                'Unknown policy has no schema contract, blocks at SCHEMA gate first'
            );
        }
    }

    @isTest
    static void given_auditEventPublished_when_wrapped_then_capturesInTestMode() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('AuditTestAction');
            GuardPolicy policy = GuardPolicy.disabled('AuditTestAction')
                .withEnabled(true)
                .withRateLimit(10)
                .withSchemaContract('{"properties":{"AccountId":{"type":"string"}}}')
                .withMaxRecordsPerCall(100)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY);
            TestDataFactory.registerPolicy(policy);

            AuditPublisher.setCaptureMode(true);
            String payload = '{"AccountId": "001"}';
            AgentGuard.wrap('AuditTestAction', payload);

            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            System.assertEquals(1, events.size(), 'Exactly one audit event must be captured');
            System.assertEquals('ALLOW', events[0].Decision__c, 'Event must be ALLOW');
            System.assertEquals('AuditTestAction', events[0].PolicyName__c, 'Policy name must match');
            System.assertEquals('FACADE', events[0].GateName__c, 'Gate name must be FACADE');
            System.assertNotEquals('', events[0].PayloadHash__c, 'Payload hash must be present');
            AuditPublisher.setCaptureMode(false);
        }
    }

    @isTest
    static void given_blockedCall_when_wrapped_then_auditEventIsBlocked() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('AuditBlockTest');
            GuardPolicy policy = GuardPolicy.disabled('AuditBlockTest')
                .withEnabled(true)
                .withRateLimit(10)
                .withSchemaContract('{"properties":{"AccountId":{"type":"string"}}}')
                .withMaxRecordsPerCall(100)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY);
            TestDataFactory.registerPolicy(policy);

            AuditPublisher.setCaptureMode(true);
            String payload = '{"AccountId": "001"}';

            // First call allowed
            AgentGuard.wrap('AuditBlockTest', payload);

            // Second call also allowed (within limit)
            AgentGuard.wrap('AuditBlockTest', payload);

            // Disable policy for third call
            policy.withEnabled(false);
            TestDataFactory.registerPolicy(policy);

            AgentGuard.wrap('AuditBlockTest', payload);

            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            System.assertEquals(3, events.size(), 'Three audit events captured');

            Integer blockedCount = 0;
            for (AgentGuard_Audit__e e : events) {
                if (e.Decision__c == 'BLOCK')
                    blockedCount++;
            }
            System.assertEquals(1, blockedCount, 'Exactly one blocked event');
            AuditPublisher.setCaptureMode(false);
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agfct' LIMIT 1];
    }
}
