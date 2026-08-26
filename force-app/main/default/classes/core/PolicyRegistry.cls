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
        return GuardPolicy.disabled(name);
    }

    private static String key(String name) {
        return name.toLowerCase();
    }
}
