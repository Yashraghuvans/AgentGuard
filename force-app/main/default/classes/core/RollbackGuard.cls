/**
 * RollbackGuard
 * ------------------------------------------------------------------
 * Opens Savepoint transaction boundaries (System.setSavepoint()) and
 * enforces max-records mutation limits per Guard_Policy__mdt.
 *
 * Security notes:
 * - Savepoint is opened BEFORE business logic executes and attached
 *   to the ALLOW GuardResult via attachSavepoint().
 * - Caller (or AgentGuard facade) MUST call rollback(result) on any
 *   exception in business logic to enforce atomicity.
 * - MaxRecordsPerCall ceiling applies to total records in the payload,
 *   not per-DML statement — prevents bulk splitting attacks.
 * - Never removes or bypasses the Savepoint boundary (RULES.md #2).
 * ------------------------------------------------------------------
 */
public inherited sharing class RollbackGuard {
    public static final String GATE_NAME = 'ROLLBACK';

    /**
     * @description Opens a Savepoint and validates record count against policy ceiling.
     * @param policy GuardPolicy domain object with maxRecordsPerCall.
     * @param payloadJson Raw JSON string from the caller.
     * @return GuardResult: ALLOW with savepoint attached, or BLOCK if ceiling exceeded.
     */
    public static GuardResult open(GuardPolicy policy, String payloadJson) {
        if (policy.maxRecordsPerCall == null || policy.maxRecordsPerCall <= 0) {
            return GuardResult.block(
                GATE_NAME,
                policy.policyName,
                policy.policyName,
                'Max records per call not configured (zero or negative)'
            );
        }

        Integer recordCount = countRecords(payloadJson);
        if (recordCount > policy.maxRecordsPerCall) {
            return GuardResult.block(
                GATE_NAME,
                policy.policyName,
                policy.policyName,
                'Record count ' + recordCount + ' exceeds policy ceiling of ' + policy.maxRecordsPerCall
            );
        }

        Savepoint sp = Database.setSavepoint();
        GuardResult result = GuardResult.allow(policy.policyName, policy.policyName);
        result.attachSavepoint(sp);
        return result;
    }

    /**
     * @description Rolls back to the savepoint attached to an ALLOW result.
     *              Call this from a catch block when business logic throws.
     * @param result GuardResult returned by open() — must be an ALLOW with savepoint.
     * @return GuardResult: ROLLBACK decision with reason.
     */
    public static GuardResult rollback(GuardResult result) {
        if (result == null || !result.isAllowed || result.getSavepoint() == null) {
            return GuardResult.rolledBack(
                result?.policyName ?? 'UNKNOWN',
                result?.actionName ?? 'UNKNOWN',
                'Rollback called on invalid or non-ALLOW result'
            );
        }

        try {
            Database.rollback(result.getSavepoint());
            return GuardResult.rolledBack(
                result.policyName,
                result.actionName,
                'Transaction rolled back due to business logic failure'
            );
        } catch (Exception e) {
            return GuardResult.rolledBack(result.policyName, result.actionName, 'Rollback failed: ' + e.getMessage());
        }
    }

    /**
     * @description Convenience: wraps business logic execution with automatic rollback on exception.
     * @param policy GuardPolicy domain object.
     * @param payloadJson Raw JSON string from the caller.
     * @param businessLogic Function that executes the actual work; receives the ALLOW result.
     * @return GuardResult from business logic, or ROLLBACK if it threw.
     */
    public static GuardResult executeWithRollback(
        GuardPolicy policy,
        String payloadJson,
        GuardResultCallback businessLogic
    ) {
        GuardResult gateResult = open(policy, payloadJson);
        if (!gateResult.isAllowed) {
            return gateResult;
        }

        try {
            return businessLogic.execute(gateResult);
        } catch (Exception e) {
            return rollback(gateResult);
        }
    }

    public interface GuardResultCallback {
        GuardResult execute(GuardResult allowResult);
    }

    private static Integer countRecords(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return 0;
        }

        try {
            Object parsed = JSON.deserializeUntyped(payloadJson);
            if (parsed instanceof List<Object>) {
                return ((List<Object>) parsed).size();
            } else if (parsed instanceof Map<String, Object>) {
                return 1;
            }
        } catch (Exception e) {
            // NOPMD - intentional: parse errors default to 0, schema validation catches them
        }
        return 0;
    }
}
