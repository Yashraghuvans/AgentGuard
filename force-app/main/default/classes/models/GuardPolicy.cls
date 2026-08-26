/**
 * GuardPolicy
 * ------------------------------------------------------------------
 * Immutable, restrictive-by-default value object representing one
 * action's policy. At v0.6 this is hydrated from a Guard_Policy__mdt
 * record; until then tests and examples construct it programmatically.
 *
 * Security note: every knob defaults to the most restrictive safe
 * value (RULES.md #5): disabled policy, zero record ceiling, zero rate
 * budget, and empty scoping lists. An unset value never means
 * "unlimited" — it means BLOCK.
 * ------------------------------------------------------------------
 */
public inherited sharing class GuardPolicy {
    /**
     * @description Data operation the wrapped action performs on the target object.
     * Member names avoid Apex reserved words (update/delete), which cannot
     * serve as identifiers.
     */
    public enum Operation {
        /**
         * @description Read path; fields checked for accessibility only.
         */
        READ,
        /**
         * @description Insert path; fields checked for create access.
         */
        CREATE,
        /**
         * @description Update path; fields checked for edit access.
         */
        MODIFY,
        /**
         * @description Delete path; object-level remove access required.
         */
        REMOVE
    }

    public static final Integer UNLIMITED_FORBIDDEN = 0;

    /**
     * @description Guard_Policy__mdt DeveloperName this policy represents.
     */
    public String policyName { get; private set; }

    /**
     * @description Master kill-switch. False (the default) blocks every call.
     */
    public Boolean isEnabled { get; private set; }

    /**
     * @description Target sObject API name the action mutates or reads.
     */
    public String targetSObjectType { get; private set; }

    /**
     * @description Operation used to select CRUD vs FLS checks in AccessGate.
     */
    public Operation operation { get; private set; }

    /**
     * @description JSON schema contract consumed by SchemaValidator.
     */
    public String schemaContractJson { get; private set; }

    /**
     * @description Max records allowed per call. Zero (default) blocks every call.
     */
    public Integer maxRecordsPerCall { get; private set; }

    /**
     * @description Max invocations per rolling window per user per action.
     * Zero (default) throttles every call.
     */
    public Integer rateLimitPerMinute { get; private set; }

    /**
     * @description Rolling-window length in seconds backing rateLimitPerMinute.
     */
    public Integer rateLimitWindowSeconds { get; private set; }

    /**
     * @description Profile names allowed to invoke the action. Empty = no extra restriction.
     */
    public Set<String> allowedProfiles { get; private set; }

    /**
     * @description Permission set names allowed to invoke the action. Empty = no extra restriction.
     */
    public Set<String> allowedPermissionSets { get; private set; }

    private GuardPolicy(String name) {
        policyName = name;
        isEnabled = false;
        targetSObjectType = '';
        operation = Operation.READ;
        schemaContractJson = '';
        maxRecordsPerCall = UNLIMITED_FORBIDDEN;
        rateLimitPerMinute = UNLIMITED_FORBIDDEN;
        rateLimitWindowSeconds = 60;
        allowedProfiles = new Set<String>();
        allowedPermissionSets = new Set<String>();
    }

    /**
     * @description Creates a fully restrictive disabled policy skeleton.
     * @param name Policy name (Guard_Policy__mdt DeveloperName).
     * @return Disabled policy whose every limit is zero.
     */
    public static GuardPolicy disabled(String name) {
        return new GuardPolicy(name);
    }

    /**
     * @description Fluent: sets the enabled flag. Policies must be explicitly enabled.
     * @param v True to allow evaluation through the gate chain.
     * @return This policy.
     */
    public GuardPolicy withEnabled(Boolean v) {
        isEnabled = v == true;
        return this;
    }

    /**
     * @description Fluent: sets the target sObject API name.
     * @param sobjectApiName e.g. 'Account'.
     * @return This policy.
     */
    public GuardPolicy withSObjectType(String sobjectApiName) {
        targetSObjectType = sobjectApiName == null ? '' : sobjectApiName.trim();
        return this;
    }

    /**
     * @description Fluent: sets the enforced operation.
     * @param op Operation enum value.
     * @return This policy.
     */
    public GuardPolicy withOperation(Operation op) {
        operation = op == null ? Operation.READ : op;
        return this;
    }

    /**
     * @description Fluent: sets the schema contract JSON consumed by SchemaValidator.
     * @param contractJson Contract document; see docs/policy-configuration.md.
     * @return This policy.
     */
    public GuardPolicy withSchemaContract(String contractJson) {
        schemaContractJson = contractJson == null ? '' : contractJson;
        return this;
    }

    /**
     * @description Fluent: sets the per-call record ceiling. Zero keeps the BLOCK default.
     * @param maxRecords Positive ceiling in records.
     * @return This policy.
     */
    public GuardPolicy withMaxRecordsPerCall(Integer maxRecords) {
        maxRecordsPerCall = maxRecords == null ? UNLIMITED_FORBIDDEN : maxRecords;
        return this;
    }

    /**
     * @description Fluent: sets the per-user-per-action invocation budget.
     * @param callsPerWindow Positive count of calls allowed per window.
     * @return This policy.
     */
    public GuardPolicy withRateLimit(Integer callsPerWindow) {
        rateLimitPerMinute = callsPerWindow == null ? UNLIMITED_FORBIDDEN : callsPerWindow;
        return this;
    }

    /**
     * @description Fluent: sets the sliding-window length. Clamped to [10, 3600].
     * @param seconds Window length in seconds.
     * @return This policy.
     */
    public GuardPolicy withRateLimitWindowSeconds(Integer seconds) {
        if (seconds == null || seconds < 10) {
            rateLimitWindowSeconds = 10;
        } else if (seconds > 3600) {
            rateLimitWindowSeconds = 3600;
        } else {
            rateLimitWindowSeconds = seconds;
        }
        return this;
    }

    /**
     * @description Fluent: restricts invocation to the given profile names.
     * @param profileNames Profile names (not Ids).
     * @return This policy.
     */
    public GuardPolicy withAllowedProfiles(Set<String> profileNames) {
        allowedProfiles = normalize(profileNames);
        return this;
    }

    /**
     * @description Fluent: restricts invocation to the given permission set names.
     * @param permSetNames Permission set names (DeveloperName or Label match).
     * @return This policy.
     */
    public GuardPolicy withAllowedPermissionSets(Set<String> permSetNames) {
        allowedPermissionSets = normalize(permSetNames);
        return this;
    }

    private static Set<String> normalize(Set<String> values) {
        Set<String> normalized = new Set<String>();
        if (values != null) {
            for (String v : values) {
                if (String.isNotBlank(v)) {
                    normalized.add(v.trim());
                }
            }
        }
        return normalized;
    }
}
