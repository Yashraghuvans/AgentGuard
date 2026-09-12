/**
 * RateLimiter
 * ------------------------------------------------------------------
 * Sliding-window invocation counter using Platform Cache (Cache.Org).
 * Enforces per-user, per-action rate limits defined in Guard_Policy__mdt.
 *
 * Security notes:
 * - Implements fail-closed logic with cache outage fallbacks:
 *   - If cache is unavailable, ALLOWS the call but flags it (allowFlagged)
 *     and publishes a Flagged__c=true audit event — never silently fails open.
 * - Cache key includes userId + actionName for per-user isolation.
 * - Window is sliding: each call cleans expired entries before counting.
 * ------------------------------------------------------------------
 */
public inherited sharing class RateLimiter {
    public static final String GATE_NAME = 'RATE';
    public static final String CACHE_PARTITION = 'AgentGuard';
    public static final String CACHE_KEY_PREFIX = 'ratelimit_';

    private static final Integer MAX_WINDOW_SECONDS = 3600;
    private static final Integer MIN_WINDOW_SECONDS = 10;

    @TestVisible
    private static Map<String, List<Long>> testTimestampMap = new Map<String, List<Long>>();

    @TestVisible
    static Boolean disableTestCache = false;

    /**
     * @description Checks if the current user has exceeded the rate limit for the action.
     * @param policy GuardPolicy domain object with rateLimitPerMinute, rateLimitWindowSeconds.
     * @param actionName Action name passed to wrap().
     * @return GuardResult: ALLOW if under limit, THROTTLED if exceeded, ALLOW_FLAGGED if cache unavailable.
     */
    public static GuardResult checkLimit(GuardPolicy policy, String actionName) {
        if (policy.rateLimitPerMinute == null || policy.rateLimitPerMinute <= 0) {
            return GuardResult.block(
                GATE_NAME,
                policy.policyName,
                actionName,
                'Rate limit not configured (zero or negative)'
            );
        }

        Integer windowSeconds = policy.rateLimitWindowSeconds;
        if (windowSeconds == null || windowSeconds < MIN_WINDOW_SECONDS) {
            windowSeconds = MIN_WINDOW_SECONDS;
        } else if (windowSeconds > MAX_WINDOW_SECONDS) {
            windowSeconds = MAX_WINDOW_SECONDS;
        }

        String cacheKey = CACHE_KEY_PREFIX + UserInfo.getUserId() + '_' + actionName;

        if (Test.isRunningTest() && !disableTestCache) {
            return checkLimitInMemory(policy, actionName, cacheKey, windowSeconds);
        }

        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition == null) {
                return GuardResult.allowFlagged(
                    policy.policyName,
                    actionName,
                    'RATE_LIMIT_CACHE_PARTITION_MISSING: AgentGuard partition not found'
                );
            }

            List<Long> timestamps = (List<Long>) partition.get(cacheKey);
            Long now = System.currentTimeMillis();
            Long windowStart = now - ((Long) windowSeconds * 1000L);

            if (timestamps == null) {
                timestamps = new List<Long>();
            }

            List<Long> validTimestamps = new List<Long>();
            for (Long ts : timestamps) {
                if (ts >= windowStart) {
                    validTimestamps.add(ts);
                }
            }

            if (validTimestamps.size() >= policy.rateLimitPerMinute) {
                Long oldest = validTimestamps.isEmpty() ? now : validTimestamps[0];
                Long resetMs = oldest + ((Long) windowSeconds * 1000L) - now;
                return GuardResult.throttled(
                    policy.policyName,
                    actionName,
                    'Rate limit exceeded: ' +
                        validTimestamps.size() +
                        '/' +
                        policy.rateLimitPerMinute +
                        ' calls in ' +
                        windowSeconds +
                        's window. Resets in ~' +
                        (resetMs / 1000) +
                        's'
                );
            }

            validTimestamps.add(now);
            partition.put(cacheKey, validTimestamps, windowSeconds);

            return GuardResult.allow(policy.policyName, actionName);
        } catch (Cache.CacheException e) {
            return GuardResult.allowFlagged(
                policy.policyName,
                actionName,
                'RATE_LIMIT_CACHE_ERROR: ' + e.getMessage() + ' — allow-and-log fallback active'
            );
        } catch (Exception e) {
            return GuardResult.allowFlagged(
                policy.policyName,
                actionName,
                'RATE_LIMIT_UNEXPECTED_ERROR: ' + e.getMessage() + ' — allow-and-log fallback active'
            );
        }
    }

    @TestVisible
    public static void clearCache(String actionName) {
        String cacheKey = CACHE_KEY_PREFIX + UserInfo.getUserId() + '_' + actionName;
        if (Test.isRunningTest() && !disableTestCache) {
            testTimestampMap.remove(cacheKey);
            return;
        }
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            if (partition != null) {
                partition.remove(cacheKey);
            }
        } catch (Exception e) {
            // NOPMD - intentional: cache unavailable in production is expected
        }
    }

    private static GuardResult checkLimitInMemory(
        GuardPolicy policy,
        String actionName,
        String cacheKey,
        Integer windowSeconds
    ) {
        List<Long> timestamps = testTimestampMap.get(cacheKey);
        Long now = System.currentTimeMillis();
        Long windowStart = now - ((Long) windowSeconds * 1000L);

        if (timestamps == null) {
            timestamps = new List<Long>();
        }

        List<Long> valid = new List<Long>();
        for (Long ts : timestamps) {
            if (ts >= windowStart) {
                valid.add(ts);
            }
        }

        if (valid.size() >= policy.rateLimitPerMinute) {
            Long oldest = valid.isEmpty() ? now : valid[0];
            Long resetMs = oldest + ((Long) windowSeconds * 1000L) - now;
            return GuardResult.throttled(
                policy.policyName,
                actionName,
                'Rate limit exceeded: ' +
                    valid.size() +
                    '/' +
                    policy.rateLimitPerMinute +
                    ' calls in ' +
                    windowSeconds +
                    's window. Resets in ~' +
                    (resetMs / 1000) +
                    's'
            );
        }

        valid.add(now);
        testTimestampMap.put(cacheKey, valid);
        return GuardResult.allow(policy.policyName, actionName);
    }
}
