/**
 * TerritoryReassignFlowTest
 * ------------------------------------------------------------------
 * Flow/Integration test for the "Almost Deleted a Territory" story
 * from the PRD. Verifies bulk-shaped payload rejection, zero state
 * corruption, and audit event capture.
 */
@isTest
private class TerritoryReassignFlowTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agtf', 'Standard User');
        // Deploy the test policy
        GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory')
            .withEnabled(true)
            .withSObjectType('Account')
            .withOperation(GuardPolicy.Operation.MODIFY)
            .withSchemaContract(
                '{"properties": {"AccountId": {"type": "string", "required": true}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}'
            )
            .withMaxRecordsPerCall(5)
            .withRateLimit(10)
            .withRateLimitWindowSeconds(60);
        TestDataFactory.registerPolicy(policy);
    }

    @isTest
    static void given_injectedBulkChurnPayload_when_agentInvokes_then_blockedAndAudited() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory')
                .withEnabled(true)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY)
                .withSchemaContract(
                    '{"properties": {"AccountId": {"type": "string"}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}'
                )
                .withMaxRecordsPerCall(5)
                .withRateLimit(10)
                .withRateLimitWindowSeconds(60);
            TestDataFactory.registerPolicy(policy);
            RateLimiter.clearCache('UpdateAccountTerritory');

            // Simulates the prompt-injection scenario: a payload shaped as a bulk mutation
            // against an action contracted for single records
            String maliciousPayload = '[{"AccountId": "001000000000001", "Territory__c": null, "Status__c": "Churned"}]';

            Test.startTest();
            GuardResult result = AgentGuard.wrap('UpdateAccountTerritory', maliciousPayload);
            Test.stopTest();

            System.assertEquals(
                false,
                result.isAllowed,
                'Bulk-shaped payload should be rejected by schema contract validation'
            );
            System.assertEquals('SCHEMA', result.gateName, 'Must be blocked at SCHEMA gate');

            // Verify an audit event was captured for this decision
            AuditPublisher.setCaptureMode(true);
            // Re-run to capture event
            AgentGuard.wrap('UpdateAccountTerritory', maliciousPayload);
            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            AuditPublisher.setCaptureMode(false);

            System.assertEquals(1, events.size(), 'Exactly one audit event for the blocked call');
            System.assertEquals('BLOCK', events[0].Decision__c, 'Decision must be BLOCK');
            System.assertEquals('SCHEMA', events[0].GateName__c, 'Gate must be SCHEMA');
        }
    }

    @isTest
    static void given_repeatedRapidCalls_when_rateLimitExceeded_then_throttledAfterThreshold() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UpdateAccountTerritory');

            // Use a policy with very low rate limit
            GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory')
                .withEnabled(true)
                .withRateLimit(3)
                .withRateLimitWindowSeconds(60)
                .withSchemaContract('{"properties": {"AccountId": {"type": "string"}}}')
                .withMaxRecordsPerCall(100)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY);
            TestDataFactory.registerPolicy(policy);

            Test.startTest();
            List<GuardResult> outcomes = new List<GuardResult>();
            for (Integer i = 0; i < 5; i++) {
                outcomes.add(AgentGuard.wrap('UpdateAccountTerritory', '{"AccountId": "001"}'));
            }
            Test.stopTest();

            Integer blockedByRateLimit = 0;
            for (GuardResult r : outcomes) {
                if (!r.isAllowed && r.decision == 'THROTTLED') {
                    blockedByRateLimit++;
                }
            }
            System.assert(blockedByRateLimit > 0, 'Calls beyond the configured RateLimitPerMinute should be throttled');
        }
    }

    @isTest
    static void given_validSingleRecord_when_processed_then_allowsAndCapturesAudit() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory')
                .withEnabled(true)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY)
                .withSchemaContract(
                    '{"properties": {"AccountId": {"type": "string"}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}'
                )
                .withMaxRecordsPerCall(5)
                .withRateLimit(10)
                .withRateLimitWindowSeconds(60);
            TestDataFactory.registerPolicy(policy);
            RateLimiter.clearCache('UpdateAccountTerritory');
            AuditPublisher.setCaptureMode(true);

            String payload = '{"AccountId": "001000000000001", "Territory__c": "West"}';
            Test.startTest();
            GuardResult result = AgentGuard.wrap('UpdateAccountTerritory', payload);
            Test.stopTest();

            System.assertEquals(true, result.isAllowed, 'Valid single record must be allowed');

            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            System.assertEquals(1, events.size(), 'One audit event for allowed call');
            System.assertEquals('ALLOW', events[0].Decision__c, 'Decision must be ALLOW');
            AuditPublisher.setCaptureMode(false);
        }
    }

    @isTest
    static void given_businessLogicThrows_when_wrapAndExecute_then_rollsBackAndAudits() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory')
                .withEnabled(true)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY)
                .withSchemaContract(
                    '{"properties": {"AccountId": {"type": "string"}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}'
                )
                .withMaxRecordsPerCall(5)
                .withRateLimit(10)
                .withRateLimitWindowSeconds(60);
            TestDataFactory.registerPolicy(policy);
            RateLimiter.clearCache('UpdateAccountTerritory');
            AuditPublisher.setCaptureMode(true);

            Test.startTest();
            GuardResult result = AgentGuard.wrapAndExecute(
                'UpdateAccountTerritory',
                '{"AccountId": "001"}',
                new ThrowingCallback()
            );
            Test.stopTest();

            System.assertEquals(false, result.isAllowed, 'Exception must trigger rollback');
            System.assertEquals('ROLLBACK', result.decision, 'Decision must be ROLLBACK');

            // Verify rollback happened
            List<Account> after = [SELECT Id FROM Account WHERE Name = 'Rollback Test'];
            System.assertEquals(0, after.size(), 'Rollback must undo DML');

            // Verify audit event for rollback
            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            Integer rollbackCount = 0;
            for (AgentGuard_Audit__e e : events) {
                if (e.Decision__c == 'ROLLBACK')
                    rollbackCount++;
            }
            System.assertEquals(1, rollbackCount, 'One ROLLBACK audit event');

            AuditPublisher.setCaptureMode(false);
        }
    }

    @isTest
    static void given_disabledPolicy_when_invoked_then_blocksWithAudit() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('UpdateAccountTerritory');
            AuditPublisher.setCaptureMode(true);

            GuardPolicy policy = GuardPolicy.disabled('UpdateAccountTerritory').withEnabled(false);
            TestDataFactory.registerPolicy(policy);

            Test.startTest();
            GuardResult result = AgentGuard.wrap('UpdateAccountTerritory', '{"AccountId": "001"}');
            Test.stopTest();

            System.assertEquals(false, result.isAllowed, 'Disabled policy must block');

            List<AgentGuard_Audit__e> events = AuditPublisher.getCapturedEvents();
            System.assertEquals(1, events.size(), 'One audit event for blocked call');
            System.assertEquals('BLOCK', events[0].Decision__c, 'Decision must be BLOCK');
            AuditPublisher.setCaptureMode(false);
        }
    }

    private class ThrowingCallback implements RollbackGuard.GuardResultCallback {
        public GuardResult execute(GuardResult allow) {
            insert new Account(Name = 'Rollback Test');
            throw new AuraHandledException('Simulated failure');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agtf' LIMIT 1];
    }
}
