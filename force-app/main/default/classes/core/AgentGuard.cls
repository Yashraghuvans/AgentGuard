/**
 * AgentGuard
 * ------------------------------------------------------------------
 * Central Facade exposing the single public entry point for action wrapping.
 * Sequentially executes: SchemaValidator → AccessGate → RateLimiter →
 * RollbackGuard → AuditPublisher.
 *
 * Fail-closed handling for unhandled exceptions (ADR-002): any exception
 * inside the gate chain is caught here and treated as a BLOCK, never
 * allowed to propagate as an ALLOW-by-default.
 *
 * Usage:
 *   GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
 *   if (!check.isAllowed) throw new AgentGuard.BlockedException(check.reason);
 *   // proceed with business logic
 * ------------------------------------------------------------------
 */
public inherited sharing class AgentGuard {
    public static final String GATE_NAME = 'FACADE';

    /**
     * @description Exception thrown by callers when wrap() returns a non-ALLOW result.
     *              Contains the decision and reason for programmatic handling.
     */
    public class BlockedException extends Exception {
        public String decision;
        public String gateName;

        public BlockedException(String reason, String decision, String gateName) {
            setMessage(reason);
            this.decision = decision;
            this.gateName = gateName;
        }
    }

    /**
     * @description Wraps an invocable action call with the full AgentGuard gate chain.
     *              This is the ONLY public entry point — callers must not invoke
     *              SchemaValidator, AccessGate, RateLimiter, or RollbackGuard directly.
     * @param policyName Guard_Policy__mdt DeveloperName (or registered test policy name).
     * @param payloadJson Raw JSON string representing the invocable request payload.
     * @return GuardResult: ALLOW with savepoint attached, or BLOCK/THROTTLED/ROLLBACK with reason.
     */
    public static GuardResult wrap(String policyName, String payloadJson) {
        Long startTime = System.currentTimeMillis();

        GuardPolicy policy = PolicyRegistry.resolve(policyName);

        try {
            GuardResult schemaResult = SchemaValidator.validate(policy, payloadJson);
            if (!schemaResult.isAllowed) {
                auditAndReturn(schemaResult, payloadJson, startTime);
                return schemaResult;
            }

            GuardResult accessResult = AccessGate.evaluate(policy, payloadJson);
            if (!accessResult.isAllowed) {
                auditAndReturn(accessResult, payloadJson, startTime);
                return accessResult;
            }

            GuardResult rateResult = RateLimiter.checkLimit(policy, policyName);
            if (!rateResult.isAllowed) {
                auditAndReturn(rateResult, payloadJson, startTime);
                return rateResult;
            }

            GuardResult rollbackResult = RollbackGuard.open(policy, payloadJson);
            if (!rollbackResult.isAllowed) {
                auditAndReturn(rollbackResult, payloadJson, startTime);
                return rollbackResult;
            }

            Long elapsed = System.currentTimeMillis() - startTime;
            GuardResult finalResult = GuardResult.allow(policyName, policyName);
            finalResult.attachSavepoint(rollbackResult.getSavepoint());

            AuditPublisher.AuditContext auditCtx = new AuditPublisher.AuditContext()
                .withPolicyName(policyName)
                .withActionName(policyName)
                .withGateName(GATE_NAME)
                .withDecision(GuardResult.DECISION_ALLOW)
                .withReason('ALLOWED_BY_POLICY')
                .withPayloadJson(payloadJson)
                .withLatencyMs(elapsed)
                .withFlagged(false);
            AuditPublisher.publish(auditCtx);

            return finalResult;
        } catch (Exception e) {
            Long elapsed = System.currentTimeMillis() - startTime;
            GuardResult failure = GuardResult.block(
                GATE_NAME,
                policyName,
                policyName,
                'Facade exception: ' + e.getMessage()
            );
            auditAndReturn(failure, payloadJson, startTime);
            return failure;
        }
    }

    /**
     * @description Convenience: wraps and executes business logic with automatic
     *              rollback on exception. Preferred pattern for most callers.
     * @param policyName Guard_Policy__mdt DeveloperName.
     * @param payloadJson Raw JSON string representing the invocable request payload.
     * @param businessLogic Function that executes the actual work.
     * @return GuardResult from business logic, or ROLLBACK if it threw, or gate BLOCK/THROTTLED.
     */
    public static GuardResult wrapAndExecute(
        String policyName,
        String payloadJson,
        RollbackGuard.GuardResultCallback businessLogic
    ) {
        Long startTime = System.currentTimeMillis();
        GuardResult gateResult = wrap(policyName, payloadJson);
        if (!gateResult.isAllowed) {
            return gateResult;
        }

        try {
            return businessLogic.execute(gateResult);
        } catch (Exception e) {
            GuardResult rolled = RollbackGuard.rollback(gateResult);
            auditAndReturn(rolled, payloadJson, startTime);
            return rolled;
        }
    }

    /**
     * @description Rolls back a previously ALLOWed call using its attached savepoint.
     *              Call this from a catch block when business logic throws.
     * @param result GuardResult returned by wrap() — must be an ALLOW with savepoint.
     * @return GuardResult: ROLLBACK decision with reason.
     */
    public static GuardResult rollback(GuardResult result) {
        return RollbackGuard.rollback(result);
    }

    private static void auditAndReturn(GuardResult result, String payloadJson, Long startTime) {
        Long elapsed = System.currentTimeMillis() - startTime;
        AuditPublisher.AuditContext auditCtx = new AuditPublisher.AuditContext()
            .withPolicyName(result.policyName)
            .withActionName(result.actionName)
            .withGateName(result.gateName)
            .withDecision(result.decision)
            .withReason(result.reason)
            .withPayloadJson(payloadJson)
            .withLatencyMs(elapsed)
            .withFlagged(result.flagged);
        AuditPublisher.publish(auditCtx);
    }
}
