/**
 * GuardResultTest
 * ------------------------------------------------------------------
 * Unit tests for the GuardResult value type, including the fail-closed
 * construction invariant: a BLOCK or THROTTLED decision without a
 * reason is rejected — a silent block is useless to the responder.
 */
@isTest
private class GuardResultTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agres', 'Standard User');
    }

    @isTest
    static void given_allowFactory_when_built_then_decisionIsAllowWithDefaultReason() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.allow('UpdateAccountTerritory', 'UpdateAccountTerritory');

            System.assertEquals(true, r.isAllowed, 'allow() must produce isAllowed=true');
            System.assertEquals(GuardResult.DECISION_ALLOW, r.decision, 'Decision string must be ALLOW');
            System.assertEquals(false, r.flagged, 'Plain allow must not be flagged');
            System.assert(String.isNotBlank(r.reason), 'ALLOW still records why it passed');
        }
    }

    @isTest
    static void given_blockFactory_when_built_then_reasonIsCarriedVerbatim() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.block('SCHEMA', 'UpdateAccountTerritory', 'unknown field: Foo__c');

            System.assertEquals(false, r.isAllowed, 'block() must produce isAllowed=false');
            System.assertEquals(GuardResult.DECISION_BLOCK, r.decision, 'Decision string must be BLOCK');
            System.assertEquals('SCHEMA', r.gateName, 'Producing gate must be recorded');
            System.assertEquals('unknown field: Foo__c', r.reason, 'Reason must survive verbatim for responders');
        }
    }

    @isTest
    static void given_throttledFactory_when_built_then_gateIsRateAndReasonSet() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.throttled(
                'UpdateAccountTerritory',
                'UpdateAccountTerritory',
                'RATE_LIMIT exceeded'
            );

            System.assertEquals(false, r.isAllowed, 'throttled() must not be allowed');
            System.assertEquals(GuardResult.DECISION_THROTTLED, r.decision, 'Decision string must be THROTTLED');
            System.assertEquals('RATE', r.gateName, 'Throttle decisions come from the RATE gate');
        }
    }

    @isTest
    static void given_flaggedAllow_when_built_then_allowStillCarriesDegradedFlag() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.allowFlagged('X', 'X', 'CACHE_UNAVAILABLE');

            System.assertEquals(true, r.isAllowed, 'Allow-and-log must still allow');
            System.assertEquals(true, r.flagged, 'But it must be visibly flagged');
            System.assertEquals('CACHE_UNAVAILABLE', r.reason, 'Flag reason must be preserved');
        }
    }

    @isTest
    static void given_rolledBackFactory_when_built_then_decisionIsRollback() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.rolledBack('X', 'X', 'mid-execution failure');

            System.assertEquals(GuardResult.DECISION_ROLLBACK, r.decision, 'Decision string must be ROLLBACK');
            System.assertEquals(false, r.isAllowed, 'Rollback outcome is never an allow');
            System.assertEquals('ROLLBACK', r.gateName, 'Rollback decisions come from the ROLLBACK gate');
        }
    }

    @isTest
    static void given_blankReasonOnBlock_when_built_then_constructionThrows() {
        System.runAs(ctxUser()) {
            Boolean threw = false;
            try {
                GuardResult.block('SCHEMA', 'X', '');
            } catch (IllegalArgumentException e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'A BLOCK without a reason is a programming error and must be rejected');
        }
    }

    @isTest
    static void given_nullReasonOnThrottle_when_built_then_constructionThrows() {
        System.runAs(ctxUser()) {
            Boolean threw = false;
            try {
                GuardResult.throttled('X', 'X', null);
            } catch (IllegalArgumentException e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'THROTTLED requires a reason');
        }
    }

    @isTest
    static void given_savepointAttachment_when_attached_then_getterExposesToken() {
        System.runAs(ctxUser()) {
            GuardResult r = GuardResult.allow('X', 'X');
            Savepoint sp = Database.setSavepoint();
            r.attachSavepoint(sp);

            System.assertEquals(sp, r.getSavepoint(), 'Facade relies on this token to roll back');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agres' LIMIT 1];
    }
}
