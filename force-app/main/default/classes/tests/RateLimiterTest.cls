/**
 * RateLimiterTest
 * ------------------------------------------------------------------
 * Unit tests for RateLimiter. Loop execution testing sliding-window
 * thresholds and throttling logic. Tests cache availability fallbacks.
 */
@isTest
private class RateLimiterTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agrat', 'Standard User');
        TestDataFactory.createUser('agratres', 'Minimum Access - Salesforce');
    }

    private static GuardPolicy rateLimitedPolicy(Integer callLimit, Integer windowSeconds) {
        return GuardPolicy.disabled('RateLimitedAction')
            .withEnabled(true)
            .withRateLimit(callLimit)
            .withRateLimitWindowSeconds(windowSeconds);
    }

    @isTest
    static void given_rateLimitNotConfigured_when_checked_then_blocks() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withRateLimit(0);
            GuardResult r = RateLimiter.checkLimit(policy, 'TestAction');

            System.assertEquals(false, r.isAllowed, 'Zero rate limit must block');
            System.assertEquals('RATE', r.gateName, 'Must be RATE gate');
        }
    }

    @isTest
    static void given_firstCallUnderLimit_when_checked_then_allows() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('FreshAction');
            GuardPolicy policy = rateLimitedPolicy(5, 60);
            GuardResult r = RateLimiter.checkLimit(policy, 'FreshAction');

            System.assertEquals(true, r.isAllowed, 'First call must be allowed');
        }
    }

    @isTest
    static void given_exceedsRateLimit_when_checked_then_throttledWithReason() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('ThrottleTest');
            GuardPolicy policy = rateLimitedPolicy(3, 60);

            for (Integer i = 0; i < 3; i++) {
                GuardResult r = RateLimiter.checkLimit(policy, 'ThrottleTest');
                System.assertEquals(true, r.isAllowed, 'Calls within limit must allow: ' + i);
            }

            GuardResult r = RateLimiter.checkLimit(policy, 'ThrottleTest');
            System.assertEquals(false, r.isAllowed, 'Fourth call must be throttled');
            System.assertEquals('RATE', r.gateName, 'Must be RATE gate');
            System.assert(r.reason.contains('Rate limit exceeded'), 'Reason must explain rate limit');
            System.assert(r.reason.contains('3/3'), 'Reason must show exceeded count');
        }
    }

    @isTest
    static void given_differentUsers_when_checked_then_independentCounters() {
        User u1 = ctxUser();
        User u2 = restrictedUser();

        RateLimiter.clearCache('MultiUserTest');
        GuardPolicy policy = rateLimitedPolicy(2, 60);

        System.runAs(u1) {
            RateLimiter.checkLimit(policy, 'MultiUserTest');
            RateLimiter.checkLimit(policy, 'MultiUserTest');
            GuardResult r = RateLimiter.checkLimit(policy, 'MultiUserTest');
            System.assertEquals(false, r.isAllowed, 'User 1 third call throttled');
        }

        System.runAs(u2) {
            GuardResult r = RateLimiter.checkLimit(policy, 'MultiUserTest');
            System.assertEquals(true, r.isAllowed, 'User 2 first call allowed');
        }
    }

    @isTest
    static void given_differentActions_when_checked_then_independentCounters() {
        System.runAs(ctxUser()) {
            RateLimiter.clearCache('ActionA');
            RateLimiter.clearCache('ActionB');
            GuardPolicy policy = rateLimitedPolicy(1, 60);

            RateLimiter.checkLimit(policy, 'ActionA');
            GuardResult r = RateLimiter.checkLimit(policy, 'ActionB');
            System.assertEquals(true, r.isAllowed, 'Different action must have separate counter');
        }
    }

    @isTest
    static void given_cachePartitionMissing_when_checked_then_allowFlagged() {
        System.runAs(ctxUser()) {
            RateLimiter.disableTestCache = true;
            try {
                GuardPolicy policy = rateLimitedPolicy(5, 60);
                GuardResult r = RateLimiter.checkLimit(policy, 'CacheMissingTest');

                System.assertEquals(true, r.isAllowed, 'Cache missing must allow (fail-open with flag)');
                System.assertEquals(true, r.flagged, 'Must be flagged as degraded mode');
            } finally {
                RateLimiter.disableTestCache = false;
            }
        }
    }

    @isTest
    static void given_windowClamping_when_windowOutOfBounds_then_clamped() {
        System.runAs(ctxUser()) {
            GuardPolicy policyLow = rateLimitedPolicy(10, 1); // Below minimum 10s
            GuardPolicy policyHigh = rateLimitedPolicy(10, 99999); // Above maximum 3600s

            // These should not throw - the policy builder clamps them
            System.assertEquals(10, policyLow.rateLimitWindowSeconds, 'Low window clamped to 10');
            System.assertEquals(3600, policyHigh.rateLimitWindowSeconds, 'High window clamped to 3600');
        }
    }

    @isTest
    static void given_realCacheMode_when_partitionNull_then_allowFlagged() {
        System.runAs(ctxUser()) {
            RateLimiter.disableTestCache = true;
            try {
                GuardPolicy policy = rateLimitedPolicy(5, 60);
                GuardResult r = RateLimiter.checkLimit(policy, 'RealCacheTest');

                // When partition is missing in real mode, it catches exception and returns allowFlagged
                System.assertEquals(true, r.isAllowed, 'Partition null must allow (degraded mode)');
                System.assertEquals(true, r.flagged, 'Must be flagged');
                // Reason should contain one of the cache error indicators
                System.assert(r.reason != null && r.reason.length() > 0, 'Reason must be present: ' + r.reason);
            } finally {
                RateLimiter.disableTestCache = false;
            }
        }
    }

    @isTest
    static void given_realCacheClear_when_invoked_then_noException() {
        System.runAs(ctxUser()) {
            RateLimiter.disableTestCache = true;
            try {
                // Should not throw even if partition missing
                RateLimiter.clearCache('ClearTestAction');
                System.assert(true, 'clearCache must not throw');
            } finally {
                RateLimiter.disableTestCache = false;
            }
        }
    }

    @isTest
    static void given_windowClampingMin_when_tooLow_then_clampsToMinimum() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = rateLimitedPolicy(10, 5); // Below min 10
            RateLimiter.clearCache('WindowMinTest');

            GuardResult r = RateLimiter.checkLimit(policy, 'WindowMinTest');
            System.assertEquals(true, r.isAllowed, 'First call must allow');
            // Window is clamped by policy builder, test confirms no exception
        }
    }

    @isTest
    static void given_windowClampingMax_when_tooHigh_then_clampsToMaximum() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = rateLimitedPolicy(10, 5000); // Above max 3600
            RateLimiter.clearCache('WindowMaxTest');

            GuardResult r = RateLimiter.checkLimit(policy, 'WindowMaxTest');
            System.assertEquals(true, r.isAllowed, 'First call must allow');
            // Window is clamped by policy builder, test confirms no exception
        }
    }

    @isTest
    static void given_nullRateLimitPerMinute_when_checked_then_blocks() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withRateLimit(null);
            GuardResult r = RateLimiter.checkLimit(policy, 'NullLimitTest');

            System.assertEquals(false, r.isAllowed, 'Null rate limit must block');
            System.assert(r.reason.contains('not configured'), 'Reason must indicate misconfiguration');
        }
    }

    @isTest
    static void given_negativeRateLimit_when_checked_then_blocks() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withRateLimit(-5);
            GuardResult r = RateLimiter.checkLimit(policy, 'NegLimitTest');

            System.assertEquals(false, r.isAllowed, 'Negative rate limit must block');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agrat' LIMIT 1];
    }

    private static User restrictedUser() {
        return [SELECT Id FROM User WHERE Alias = 'agratres' LIMIT 1];
    }
}
