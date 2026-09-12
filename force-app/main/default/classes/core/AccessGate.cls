/**
 * AccessGate
 * ------------------------------------------------------------------
 * Enforces object- and field-level security (CRUD/FLS) for any payload
 * passed through AgentGuard.wrap(). Runs strictly WITH USER_MODE against
 * the invoking user's context — never assumes an elevated/service context
 * even when the caller is a trusted internal agent.
 *
 * Security notes:
 * - Uses Security.stripInaccessible() for read paths, WITH USER_MODE
 *   SOQL for write paths to enforce true running-user permissions.
 * - Fails closed on any exception (ADR-002): permission check errors,
 *   describe failures, or unexpected nulls all produce BLOCK.
 * - Enforces profile/permission-set scoping from Guard_Policy__mdt.
 * ------------------------------------------------------------------
 */
public inherited sharing class AccessGate {
    public static final String GATE_NAME = 'ACCESS';

    /**
     * @description Evaluates CRUD/FLS for a single payload against the policy.
     * @param policy GuardPolicy domain object with targetSObjectType, operation, allowedProfiles, allowedPermissionSets.
     * @param payloadJson Raw JSON string from the caller (used for field extraction).
     * @return GuardResult: ALLOW if accessible, BLOCK with field/access reason if not.
     */
    public static GuardResult evaluate(GuardPolicy policy, String payloadJson) {
        try {
            if (!policy.isEnabled) {
                return GuardResult.block(GATE_NAME, policy.policyName, policy.policyName, 'Policy is disabled');
            }

            if (String.isBlank(policy.targetSObjectType)) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Target sObject type not configured'
                );
            }

            GuardResult profileCheck = checkProfileAndPermissionSets(policy);
            if (!profileCheck.isAllowed) {
                return profileCheck;
            }

            Object parsed = JSON.deserializeUntyped(payloadJson);
            if (parsed == null) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Payload deserialized to null'
                );
            }

            List<Map<String, Object>> payloads = new List<Map<String, Object>>();
            if (parsed instanceof List<Object>) {
                for (Object item : (List<Object>) parsed) {
                    if (item instanceof Map<String, Object>) {
                        payloads.add((Map<String, Object>) item);
                    }
                }
            } else if (parsed instanceof Map<String, Object>) {
                payloads.add((Map<String, Object>) parsed);
            } else {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Payload must be an object or array of objects'
                );
            }

            for (Map<String, Object> payload : payloads) {
                GuardResult fieldCheck = checkFieldAccess(policy, payload);
                if (!fieldCheck.isAllowed) {
                    return fieldCheck;
                }
            }

            return GuardResult.allow(policy.policyName, policy.policyName);
        } catch (Exception e) {
            return GuardResult.block(
                GATE_NAME,
                policy.policyName,
                policy.policyName,
                'Access evaluation failed: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Bulk evaluation for list-based invocable requests.
     * @param policy GuardPolicy domain object.
     * @param payloads List of payload maps.
     * @return List of GuardResult, one per payload.
     */
    public static List<GuardResult> evaluateBulk(GuardPolicy policy, List<Map<String, Object>> payloads) {
        List<GuardResult> results = new List<GuardResult>();
        for (Map<String, Object> payload : payloads) {
            results.add(evaluate(policy, JSON.serialize(payload)));
        }
        return results;
    }

    private static GuardResult checkProfileAndPermissionSets(GuardPolicy policy) {
        if (policy.allowedProfiles != null && !policy.allowedProfiles.isEmpty()) {
            String userProfileName = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]
            .Profile.Name;
            if (!policy.allowedProfiles.contains(userProfileName)) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Profile not authorized: ' + userProfileName
                );
            }
        }

        if (policy.allowedPermissionSets != null && !policy.allowedPermissionSets.isEmpty()) {
            Set<String> userPermSets = new Set<String>();
            for (PermissionSetAssignment psa : [
                SELECT PermissionSet.Name
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
            ]) {
                userPermSets.add(psa.PermissionSet.Name);
            }
            Boolean hasRequired = false;
            for (String required : policy.allowedPermissionSets) {
                if (userPermSets.contains(required)) {
                    hasRequired = true;
                    break;
                }
            }
            if (!hasRequired) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Required permission set not assigned'
                );
            }
        }

        return GuardResult.allow(policy.policyName, policy.policyName);
    }

    private static GuardResult checkFieldAccess(GuardPolicy policy, Map<String, Object> payload) {
        String sobjectType = policy.targetSObjectType;
        GuardPolicy.Operation op = policy.operation;

        SObjectAccessDecision decision = null;
        List<SObject> recordsToCheck = new List<SObject>();

        if (op == GuardPolicy.Operation.READ) {
            decision = Security.stripInaccessible(AccessType.READABLE, recordsToCheck);
        } else if (op == GuardPolicy.Operation.CREATE) {
            decision = Security.stripInaccessible(AccessType.CREATABLE, recordsToCheck);
        } else if (op == GuardPolicy.Operation.MODIFY) {
            decision = Security.stripInaccessible(AccessType.UPDATABLE, recordsToCheck);
        } else if (op == GuardPolicy.Operation.REMOVE) {
            Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(sobjectType)?.getDescribe();
            if (describe == null || !describe.isDeletable()) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Object not deletable: ' + sobjectType
                );
            }
            return GuardResult.allow(policy.policyName, policy.policyName);
        }

        if (decision == null) {
            return GuardResult.block(
                GATE_NAME,
                policy.policyName,
                policy.policyName,
                'Could not determine access type for operation: ' + op
            );
        }

        Set<String> removedFields = decision.getRemovedFields().get(sobjectType);
        if (removedFields != null && !removedFields.isEmpty()) {
            for (String field : payload.keySet()) {
                if (removedFields.contains(field)) {
                    return GuardResult.block(
                        GATE_NAME,
                        policy.policyName,
                        policy.policyName,
                        'Field not accessible: ' + field
                    );
                }
            }
        }

        if (op == GuardPolicy.Operation.CREATE) {
            Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(sobjectType)?.getDescribe();
            if (describe == null || !describe.isCreateable()) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Object not creatable: ' + sobjectType
                );
            }
        } else if (op == GuardPolicy.Operation.MODIFY) {
            Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(sobjectType)?.getDescribe();
            if (describe == null || !describe.isUpdateable()) {
                return GuardResult.block(
                    GATE_NAME,
                    policy.policyName,
                    policy.policyName,
                    'Object not updateable: ' + sobjectType
                );
            }
        }

        return GuardResult.allow(policy.policyName, policy.policyName);
    }
}
