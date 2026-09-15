/**
 * PolicyRegistryTest
 * ------------------------------------------------------------------
 * Unit tests for PolicyRegistry metadata resolution and test-mode
 * override mechanics.
 */
@isTest
private class PolicyRegistryTest {
    @isTest
    static void given_unknownPolicy_when_resolved_then_returnsDisabled() {
        GuardPolicy policy = PolicyRegistry.resolve('UnknownPolicyName');

        System.assertNotEquals(null, policy, 'Must never return null');
        System.assertEquals(false, policy.isEnabled, 'Unknown policy must be disabled');
        System.assertEquals('UnknownPolicyName', policy.policyName, 'Policy name must match requested');
        System.assertEquals(0, policy.maxRecordsPerCall, 'Max records must be zero (restrictive default)');
        System.assertEquals(0, policy.rateLimitPerMinute, 'Rate limit must be zero (restrictive default)');
    }

    @isTest
    static void given_testOverride_when_resolved_then_returnsOverride() {
        GuardPolicy expected = GuardPolicy.disabled('TestPolicy')
            .withEnabled(true)
            .withRateLimit(100)
            .withMaxRecordsPerCall(50);

        PolicyRegistry.registerForTesting(expected);

        GuardPolicy actual = PolicyRegistry.resolve('TestPolicy');
        System.assertEquals(true, actual.isEnabled, 'Must return registered policy');
        System.assertEquals(100, actual.rateLimitPerMinute, 'Must match registered rate limit');
        System.assertEquals(50, actual.maxRecordsPerCall, 'Must match registered max records');

        PolicyRegistry.clearForTesting();
    }

    @isTest
    static void given_multiplePolicies_when_registered_then_resolvedIndependently() {
        GuardPolicy policy1 = GuardPolicy.disabled('Policy1').withEnabled(true).withRateLimit(10);
        GuardPolicy policy2 = GuardPolicy.disabled('Policy2').withEnabled(true).withRateLimit(20);

        PolicyRegistry.registerForTesting(policy1);
        PolicyRegistry.registerForTesting(policy2);

        GuardPolicy resolved1 = PolicyRegistry.resolve('Policy1');
        GuardPolicy resolved2 = PolicyRegistry.resolve('Policy2');

        System.assertEquals(10, resolved1.rateLimitPerMinute, 'Policy1 rate limit must match');
        System.assertEquals(20, resolved2.rateLimitPerMinute, 'Policy2 rate limit must match');

        PolicyRegistry.clearForTesting();
    }

    @isTest
    static void given_clearForTesting_when_invoked_then_removesAllOverrides() {
        GuardPolicy policy = GuardPolicy.disabled('TestClear').withEnabled(true);
        PolicyRegistry.registerForTesting(policy);

        PolicyRegistry.clearForTesting();

        GuardPolicy resolved = PolicyRegistry.resolve('TestClear');
        System.assertEquals(false, resolved.isEnabled, 'Cleared policy must revert to disabled default');
    }

    @isTest
    static void given_nullOrBlankName_when_registered_then_throws() {
        GuardPolicy policy = GuardPolicy.disabled('');

        try {
            PolicyRegistry.registerForTesting(policy);
            System.assert(false, 'Should have thrown IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('named policy'), 'Exception must explain requirement');
        }
    }

    @isTest
    static void given_caseInsensitiveKey_when_resolved_then_matches() {
        GuardPolicy policy = GuardPolicy.disabled('MixedCase').withEnabled(true).withRateLimit(42);
        PolicyRegistry.registerForTesting(policy);

        GuardPolicy lower = PolicyRegistry.resolve('mixedcase');
        GuardPolicy upper = PolicyRegistry.resolve('MIXEDCASE');

        System.assertEquals(42, lower.rateLimitPerMinute, 'Lowercase key must resolve');
        System.assertEquals(42, upper.rateLimitPerMinute, 'Uppercase key must resolve');

        PolicyRegistry.clearForTesting();
    }

    @isTest
    static void given_metadataQueryReturnsEmpty_when_resolved_then_returnsDisabled() {
        // No test override registered — forces metadata path
        PolicyRegistry.clearForTesting();

        // Resolving non-existent metadata record
        GuardPolicy policy = PolicyRegistry.resolve('NonExistentMdtRecord');

        System.assertNotEquals(null, policy, 'Must never return null');
        System.assertEquals(false, policy.isEnabled, 'Non-existent metadata must return disabled policy');
        System.assertEquals('NonExistentMdtRecord', policy.policyName, 'Policy name must match requested');
    }

    @isTest
    static void given_metadataQueryCache_when_resolvedTwice_then_returnsCached() {
        // No test override — forces metadata fetch
        PolicyRegistry.clearForTesting();

        GuardPolicy first = PolicyRegistry.resolve('SomeUnknownPolicy');
        GuardPolicy second = PolicyRegistry.resolve('SomeUnknownPolicy');

        // Both should return the same disabled policy (cached after first fetch)
        System.assertEquals(first.policyName, second.policyName, 'Cached policy name must match');
        System.assertEquals(first.isEnabled, second.isEnabled, 'Cached enabled state must match');
    }

    @isTest
    static void given_blankPolicyName_when_resolved_then_returnsDisabled() {
        PolicyRegistry.clearForTesting();

        GuardPolicy policy = PolicyRegistry.resolve('');

        System.assertNotEquals(null, policy, 'Must never return null even for blank name');
        System.assertEquals(false, policy.isEnabled, 'Blank name must return disabled policy');
    }

    @isTest
    static void given_nullPolicyName_when_resolved_then_returnsDisabled() {
        PolicyRegistry.clearForTesting();

        GuardPolicy policy = PolicyRegistry.resolve(null);

        System.assertNotEquals(null, policy, 'Must never return null even for null name');
        System.assertEquals(false, policy.isEnabled, 'Null name must return disabled policy');
    }
}
