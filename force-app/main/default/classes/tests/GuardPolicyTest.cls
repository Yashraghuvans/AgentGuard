/**
 * GuardPolicyTest
 * ------------------------------------------------------------------
 * Unit tests for the GuardPolicy value type. The critical assertion
 * set proves the restrictive-by-default posture required by RULES.md
 * #5: every unset knob blocks, nothing is permissive by default.
 */
@isTest
private class GuardPolicyTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agpol', 'Standard User');
    }

    @isTest
    static void given_freshPolicy_when_inspected_then_everyKnobDefaultsRestrictive() {
        System.runAs(ctxUser()) {
            GuardPolicy p = GuardPolicy.disabled('SomeAction');

            System.assertEquals(false, p.isEnabled, 'Policies must ship disabled');
            System.assertEquals(0, p.maxRecordsPerCall, 'Zero record ceiling must BLOCK, not allow unlimited');
            System.assertEquals(0, p.rateLimitPerMinute, 'Zero rate budget must THROTTLE, not allow unlimited');
            System.assertEquals(60, p.rateLimitWindowSeconds, 'Default window should be 60s');
            System.assertEquals('', p.targetSObjectType, 'No implicit target object');
            System.assertEquals('', p.schemaContractJson, 'No implicit schema contract');
            System.assertEquals(true, p.allowedProfiles.isEmpty(), 'Scoping starts empty');
            System.assertEquals(true, p.allowedPermissionSets.isEmpty(), 'Scoping starts empty');
        }
    }

    @isTest
    static void given_fluentConfiguration_when_built_then_everyValueSticks() {
        String contract = '{"fields":{"AccountId":{"type":"id","required":true}}}';

        System.runAs(ctxUser()) {
            GuardPolicy p = GuardPolicy.disabled('UpdateAccountTerritory')
                .withEnabled(true)
                .withSObjectType('Account')
                .withOperation(GuardPolicy.Operation.MODIFY)
                .withSchemaContract(contract)
                .withMaxRecordsPerCall(5)
                .withRateLimit(10)
                .withRateLimitWindowSeconds(30)
                .withAllowedProfiles(new Set<String>{ 'Agentforce Service Agent' })
                .withAllowedPermissionSets(new Set<String>{ 'Agent_Tools' });

            System.assertEquals(true, p.isEnabled, 'Enable flag must stick');
            System.assertEquals('Account', p.targetSObjectType, 'Target object must stick');
            System.assertEquals(GuardPolicy.Operation.MODIFY, p.operation, 'Operation must stick');
            System.assertEquals(contract, p.schemaContractJson, 'Contract JSON must be preserved verbatim');
            System.assertEquals(5, p.maxRecordsPerCall, 'Record ceiling must stick');
            System.assertEquals(10, p.rateLimitPerMinute, 'Rate budget must stick');
            System.assertEquals(30, p.rateLimitWindowSeconds, 'Window length must stick');
            System.assertEquals(
                new Set<String>{ 'Agentforce Service Agent' },
                p.allowedProfiles,
                'Profile scoping must stick'
            );
            System.assertEquals(
                new Set<String>{ 'Agent_Tools' },
                p.allowedPermissionSets,
                'Permset scoping must stick'
            );
        }
    }

    @isTest
    static void given_nullInputs_when_building_then_valuesFallBackRestrictive() {
        System.runAs(ctxUser()) {
            GuardPolicy p = GuardPolicy.disabled('X')
                .withEnabled(null)
                .withSObjectType(null)
                .withOperation(null)
                .withSchemaContract(null)
                .withMaxRecordsPerCall(null)
                .withRateLimit(null)
                .withRateLimitWindowSeconds(null)
                .withAllowedProfiles(null)
                .withAllowedPermissionSets(null);

            System.assertEquals(false, p.isEnabled, 'null enable must stay disabled');
            System.assertEquals(0, p.maxRecordsPerCall, 'null ceiling must stay at blocking zero');
            System.assertEquals(0, p.rateLimitPerMinute, 'null budget must stay at throttling zero');
            System.assertEquals(
                GuardPolicy.Operation.READ,
                p.operation,
                'null operation falls back to least-privileged READ'
            );
            System.assertEquals(false, String.isNotBlank(p.targetSObjectType), 'target stays blank-safe');
        }
    }

    @isTest
    static void given_windowBounds_when_clamped_then_staysWithinSafeRange() {
        System.runAs(ctxUser()) {
            Integer tooLow = GuardPolicy.disabled('A').withRateLimitWindowSeconds(1).rateLimitWindowSeconds;
            Integer tooHigh = GuardPolicy.disabled('B').withRateLimitWindowSeconds(99999).rateLimitWindowSeconds;

            System.assertEquals(10, tooLow, 'Windows below 10s clamp up to avoid cache thrash');
            System.assertEquals(3600, tooHigh, 'Windows above 1h clamp down to bound cache growth');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agpol' LIMIT 1];
    }
}
