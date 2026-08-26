/**
 * GuardResult
 * ------------------------------------------------------------------
 * Immutable value type returned by every AgentGuard gate and by the
 * AgentGuard.wrap() facade. Carries the decision (ALLOW, BLOCK,
 * THROTTLED, ROLLBACK), a human-readable reason that is mandatory on
 * every non-ALLOW outcome, and — for ALLOWED calls — the Savepoint
 * token opened by RollbackGuard so callers can roll back mid-execution
 * failures via AgentGuard.rollback(result).
 *
 * Security note: factories enforce the fail-closed invariant at
 * construction time. A BLOCK or THROTTLED result without a reason is
 * treated as a programming error and rejected with an exception.
 * ------------------------------------------------------------------
 */
@SuppressWarnings('PMD.ClassNamingConventions')
public inherited sharing class GuardResult {
    public static final String DECISION_ALLOW = 'ALLOW';
    public static final String DECISION_BLOCK = 'BLOCK';
    public static final String DECISION_THROTTLED = 'THROTTLED';
    public static final String DECISION_ROLLBACK = 'ROLLBACK';

    /**
     * @description True only when decision is ALLOW.
     */
    public Boolean isAllowed { get; private set; }

    /**
     * @description Machine-readable decision: ALLOW | BLOCK | THROTTLED | ROLLBACK.
     */
    public String decision { get; private set; }

    /**
     * @description Human-readable reason; always populated for non-ALLOW decisions.
     */
    public String reason { get; private set; }

    /**
     * @description Guard_Policy__mdt DeveloperName the call was evaluated against.
     */
    public String policyName { get; private set; }

    /**
     * @description Action name supplied to wrap(); mirrors policyName in v1.
     */
    public String actionName { get; private set; }

    /**
     * @description Gate that produced the decision: FACADE | SCHEMA | ACCESS | RATE | ROLLBACK.
     */
    public String gateName { get; private set; }

    /**
     * @description True when this ALLOW carries a documented degraded-mode flag
     * (e.g. rate limiter allow-and-log during a Platform Cache outage).
     */
    public Boolean flagged { get; private set; }

    @TestVisible
    private Savepoint savepointToken;

    private GuardResult(
        Boolean allowed,
        String decisionValue,
        String reasonValue,
        String policy,
        String action,
        String gate,
        Boolean flaggedValue
    ) {
        isAllowed = allowed;
        decision = decisionValue;
        reason = reasonValue;
        policyName = policy;
        actionName = action;
        gateName = gate;
        flagged = flaggedValue;
    }

    /**
     * @description Builds an ALLOW decision.
     * @param policy Guard_Policy__mdt DeveloperName evaluated.
     * @param action Action name passed to wrap().
     * @return ALLOW result with a non-blank default reason.
     */
    public static GuardResult allow(String policy, String action) {
        return new GuardResult(true, DECISION_ALLOW, 'ALLOWED_BY_POLICY', policy, action, 'FACADE', false);
    }

    /**
     * @description Builds a degraded-mode ALLOW that still ships a visible flag and reason.
     * @param policy Guard_Policy__mdt DeveloperName evaluated.
     * @param action Action name passed to wrap().
     * @param why Reason string explaining the degraded mode (never blank).
     * @return ALLOW result with flagged=true.
     */
    public static GuardResult allowFlagged(String policy, String action, String why) {
        validateReason(why, DECISION_ALLOW + '_FLAGGED');
        return new GuardResult(true, DECISION_ALLOW, why, policy, action, 'RATE', true);
    }

    /**
     * @description Builds a BLOCK decision produced by a specific gate.
     * @param gate Producing gate name: SCHEMA | ACCESS | RATE | ROLLBACK | FACADE.
     * @param policy Guard_Policy__mdt DeveloperName evaluated.
     * @param action Action name passed to wrap().
     * @param why Reason string naming the violated rule or field (never blank).
     * @return BLOCK result.
     */
    public static GuardResult block(String gate, String policy, String action, String why) {
        validateReason(why, DECISION_BLOCK);
        return new GuardResult(false, DECISION_BLOCK, why, policy, action, gate, false);
    }

    /**
     * @description Builds a THROTTLED decision from the RateLimiter gate.
     * @param policy Guard_Policy__mdt DeveloperName evaluated.
     * @param action Action name passed to wrap().
     * @param why Reason string including the exhausted budget detail (never blank).
     * @return THROTTLED result.
     */
    public static GuardResult throttled(String policy, String action, String why) {
        validateReason(why, DECISION_THROTTLED);
        return new GuardResult(false, DECISION_THROTTLED, why, policy, action, 'RATE', false);
    }

    /**
     * @description Builds a ROLLBACK decision recorded after RollbackGuard undoes DML.
     * @param policy Guard_Policy__mdt DeveloperName evaluated.
     * @param action Action name passed to wrap().
     * @param why Reason string describing what triggered the rollback (never blank).
     * @return ROLLBACK result.
     */
    public static GuardResult rolledBack(String policy, String action, String why) {
        validateReason(why, DECISION_ROLLBACK);
        return new GuardResult(false, DECISION_ROLLBACK, why, policy, action, 'ROLLBACK', false);
    }

    /**
     * @description Attaches the Savepoint opened by RollbackGuard to an ALLOW result.
     *              Framework-internal: only RollbackGuard/facade code should call this.
     * @param sp Savepoint opened immediately before business logic executes.
     */
    public void attachSavepoint(Savepoint sp) {
        savepointToken = sp;
    }

    private static void validateReason(String why, String decisionLabel) {
        if (why == null || why.trim().isEmpty()) {
            throw new IllegalArgumentException(decisionLabel + ' requires a non-blank reason');
        }
    }
}
