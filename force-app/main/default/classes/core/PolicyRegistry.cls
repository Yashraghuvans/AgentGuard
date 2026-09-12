/**
 * PolicyRegistry
 * ------------------------------------------------------------------
 * Resolves the GuardPolicy for a given policy name.
 *
 * v0.1 behavior: resolves from an in-memory test registry; any
 * unknown name resolves to GuardPolicy.disabled(name), which blocks
 * every call — fail closed by construction (ADR-002).
 *
 * v0.6 behavior (issue #13): resolution is replaced by live
 * Guard_Policy__mdt lookups cached per transaction. The test registry
 * keeps precedence so unit tests stay hermetic.
 * ------------------------------------------------------------------
 */
public inherited sharing class PolicyRegistry {
    @TestVisible
    private static Map<String, GuardPolicy> testOverrides = new Map<String, GuardPolicy>();

    @TestVisible
    private static Map<String, GuardPolicy> metadataCache = new Map<String, GuardPolicy>();

    private static final String MDT_TYPE = 'Guard_Policy__mdt';

    /**
     * @description Registers a programmatic policy override for tests and examples.
     * @param policy Fully configured GuardPolicy to register under its own name.
     */
    public static void registerForTesting(GuardPolicy policy) {
        if (policy == null || String.isBlank(policy.policyName)) {
            throw new IllegalArgumentException('registerForTesting requires a named policy');
        }
        testOverrides.put(key(policy.policyName), policy);
    }

    /**
     * @description Clears every registered test override.
     */
    public static void clearForTesting() {
        testOverrides.clear();
    }

    /**
     * @description Resolves the effective policy for a name. Unknown names resolve
     *              to a disabled (all-blocking) policy, never null.
     * @param name Policy name as passed to AgentGuard.wrap().
     * @return Effective GuardPolicy; never null.
     */
    public static GuardPolicy resolve(String name) {
        if (String.isNotBlank(name) && testOverrides.containsKey(key(name))) {
            return testOverrides.get(key(name));
        }

        if (String.isNotBlank(name) && metadataCache.containsKey(key(name))) {
            return metadataCache.get(key(name));
        }

        GuardPolicy policy = fetchFromMetadata(name);
        if (policy != null) {
            metadataCache.put(key(name), policy);
            return policy;
        }

        return GuardPolicy.disabled(name);
    }

    private static GuardPolicy fetchFromMetadata(String name) {
        try {
            List<Guard_Policy__mdt> records = [
                SELECT
                    DeveloperName,
                    IsActive__c,
                    TargetSObjectType__c,
                    Operation__c,
                    SchemaContract__c,
                    MaxRecordsPerCall__c,
                    RateLimitPerMinute__c,
                    RateLimitWindowSeconds__c,
                    AllowedProfiles__c,
                    AllowedPermissionSets__c
                FROM Guard_Policy__mdt
                WHERE DeveloperName = :name
                LIMIT 1
            ];

            if (records.isEmpty()) {
                return null;
            }

            Guard_Policy__mdt record = records[0];
            GuardPolicy policy = GuardPolicy.disabled(record.DeveloperName)
                .withEnabled(record.IsActive__c)
                .withSObjectType(record.TargetSObjectType__c)
                .withOperation(mapOperation(record.Operation__c))
                .withSchemaContract(record.SchemaContract__c)
                .withMaxRecordsPerCall((Integer) record.MaxRecordsPerCall__c)
                .withRateLimit((Integer) record.RateLimitPerMinute__c)
                .withRateLimitWindowSeconds((Integer) record.RateLimitWindowSeconds__c)
                .withAllowedProfiles(parseSemicolonList(record.AllowedProfiles__c))
                .withAllowedPermissionSets(parseSemicolonList(record.AllowedPermissionSets__c));

            return policy;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'PolicyRegistry metadata fetch failed for ' + name + ': ' + e.getMessage()
            );
            return null;
        }
    }

    private static GuardPolicy.Operation mapOperation(String value) {
        if (String.isBlank(value)) {
            return GuardPolicy.Operation.READ;
        }
        try {
            return (GuardPolicy.Operation) GuardPolicy.Operation.valueOf(value.toUpperCase());
        } catch (Exception e) {
            return GuardPolicy.Operation.READ;
        }
    }

    private static Set<String> parseSemicolonList(String value) {
        Set<String> result = new Set<String>();
        if (String.isNotBlank(value)) {
            for (String part : value.split(';')) {
                String trimmed = part.trim();
                if (String.isNotBlank(trimmed)) {
                    result.add(trimmed);
                }
            }
        }
        return result;
    }

    private static String key(String name) {
        return name.toLowerCase();
    }
}
