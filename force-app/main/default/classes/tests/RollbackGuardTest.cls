/**
 * RollbackGuardTest
 * ------------------------------------------------------------------
 * Unit tests for RollbackGuard. Boundary tests verifying Savepoint
 * rollbacks when record limits are breached or business logic throws.
 */
@isTest
private class RollbackGuardTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agrb', 'Standard User');
    }

    private static GuardPolicy limitedPolicy(Integer maxRecords) {
        return GuardPolicy.disabled('LimitedAction').withEnabled(true).withMaxRecordsPerCall(maxRecords);
    }

    @isTest
    static void given_recordCountUnderLimit_when_opened_then_allowsWithSavepoint() {
        System.runAs(ctxUser()) {
            String payload = '[{"Id": "001"}, {"Id": "002"}]';
            GuardResult r = RollbackGuard.open(limitedPolicy(5), payload);

            System.assertEquals(true, r.isAllowed, 'Under limit must allow');
            System.assertNotEquals(null, r.getSavepoint(), 'Savepoint must be attached');
        }
    }

    @isTest
    static void given_recordCountExceedsLimit_when_opened_then_blocks() {
        System.runAs(ctxUser()) {
            String payload = '[{"Id": "001"}, {"Id": "002"}, {"Id": "003"}]';
            GuardResult r = RollbackGuard.open(limitedPolicy(2), payload);

            System.assertEquals(false, r.isAllowed, 'Over limit must block');
            System.assertEquals('ROLLBACK', r.gateName, 'Must be ROLLBACK gate');
            System.assert(r.reason.contains('exceeds policy ceiling'), 'Reason must explain limit');
        }
    }

    @isTest
    static void given_zeroMaxRecords_when_opened_then_blocks() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = limitedPolicy(0);
            GuardResult r = RollbackGuard.open(policy, '{"Id": "001"}');

            System.assertEquals(false, r.isAllowed, 'Zero ceiling must block');
            System.assertEquals('ROLLBACK', r.gateName, 'Must be ROLLBACK gate');
        }
    }

    @isTest
    static void given_rollbackOnException_when_rolledBack_then_returnsRollbackResult() {
        System.runAs(ctxUser()) {
            String payload = '[{"Id": "001"}]';

            Test.startTest();
            GuardResult allow = RollbackGuard.open(limitedPolicy(5), payload);
            System.assertEquals(true, allow.isAllowed, 'Precondition: open must allow');
            System.assertNotEquals(null, allow.getSavepoint(), 'Savepoint must be attached');

            Account acc = new Account(Name = 'Test Rollback');
            insert acc;

            GuardResult rolled = RollbackGuard.rollback(allow);
            Test.stopTest();

            System.assertEquals(false, rolled.isAllowed, 'Rollback result must not be allowed');
            System.assertEquals('ROLLBACK', rolled.decision, 'Decision must be ROLLBACK');
            System.assertEquals('ROLLBACK', rolled.gateName, 'Gate must be ROLLBACK');
            System.assert(rolled.reason.contains('rolled back'), 'Reason must describe rollback');

            List<Account> after = [SELECT Id FROM Account WHERE Name = 'Test Rollback'];
            System.assertEquals(0, after.size(), 'Rollback must undo DML');
        }
    }

    @isTest
    static void given_rollbackOnNullResult_when_rolledBack_then_returnsRollbackWithError() {
        System.runAs(ctxUser()) {
            GuardResult rolled = RollbackGuard.rollback(null);
            System.assertEquals(false, rolled.isAllowed, 'Null result must not allow');
            System.assertEquals('UNKNOWN', rolled.policyName, 'Policy name must be UNKNOWN');
        }
    }

    @isTest
    static void given_rollbackOnNonAllowResult_when_rolledBack_then_returnsRollbackWithError() {
        System.runAs(ctxUser()) {
            GuardResult blocked = GuardResult.block('SCHEMA', 'Test', 'Test', 'bad');
            GuardResult rolled = RollbackGuard.rollback(blocked);

            System.assertEquals(false, rolled.isAllowed, 'Blocked result must not allow');
            System.assert(rolled.reason.contains('non-ALLOW'), 'Reason must explain invalid input');
        }
    }

    @isTest
    static void given_executeWithRollback_when_callbackThrows_then_rollsBackAndReturnsRollback() {
        System.runAs(ctxUser()) {
            String payload = '[{"Id": "001"}]';
            GuardPolicy policy = limitedPolicy(5);

            GuardResult result = RollbackGuard.executeWithRollback(policy, payload, new ThrowingCallback());

            System.assertEquals(false, result.isAllowed, 'Exception must trigger rollback');
            System.assertEquals('ROLLBACK', result.decision, 'Decision must be ROLLBACK');

            List<Account> after = [SELECT Id FROM Account WHERE Name = 'Should Rollback'];
            System.assertEquals(0, after.size(), 'Rollback must undo DML from callback');
        }
    }

    @isTest
    static void given_executeWithRollback_when_callbackSucceeds_then_returnsCallbackResult() {
        System.runAs(ctxUser()) {
            String payload = '[{"Id": "001"}]';
            GuardPolicy policy = limitedPolicy(5);

            GuardResult result = RollbackGuard.executeWithRollback(policy, payload, new SucceedingCallback());

            System.assertEquals(true, result.isAllowed, 'Success must return callback result');
            System.assertEquals('Custom', result.policyName, 'Must return callback policy name');
        }
    }

    @isTest
    static void given_singleObjectPayload_when_counted_then_countsAsOne() {
        System.runAs(ctxUser()) {
            String payload = '{"Id": "001", "Name": "Test"}';
            GuardResult r = RollbackGuard.open(limitedPolicy(1), payload);
            System.assertEquals(true, r.isAllowed, 'Single object counts as 1');
        }
    }

    @isTest
    static void given_emptyPayload_when_counted_then_countsAsZero() {
        System.runAs(ctxUser()) {
            String payload = '';
            GuardResult r = RollbackGuard.open(limitedPolicy(1), payload);
            System.assertEquals(true, r.isAllowed, 'Empty payload counts as 0');
        }
    }

    private class ThrowingCallback implements RollbackGuard.GuardResultCallback {
        public GuardResult execute(GuardResult allow) {
            insert new Account(Name = 'Should Rollback');
            throw new AuraHandledException('Simulated failure');
        }
    }

    private class SucceedingCallback implements RollbackGuard.GuardResultCallback {
        public GuardResult execute(GuardResult allow) {
            return GuardResult.allow('Custom', 'Action');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agrb' LIMIT 1];
    }
}
