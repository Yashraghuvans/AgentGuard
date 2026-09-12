/**
 * SchemaValidator
 * ------------------------------------------------------------------
 * Validates AI JSON payload keys, data types, and required fields
 * against declared contracts in Guard_Policy__mdt.SchemaContract__c.
 *
 * Security notes:
 * - Rejects payloads with unknown top-level keys (ADR-002: fail closed).
 * - Treats malformed JSON as a BLOCK, not an exception — caller never
 *   sees a parse error, only a GuardResult with decision=BLOCK.
 * - Uses JSON.deserializeUntyped to avoid type confusion attacks.
 * ------------------------------------------------------------------
 */
public inherited sharing class SchemaValidator {
    /**
     * @description Validates a payload against the policy's schema contract.
     * @param policy GuardPolicy domain object with schemaContractJson populated.
     * @param payloadJson Raw JSON string from the caller.
     * @return GuardResult: ALLOW if valid, BLOCK with reason if invalid.
     */
    public static GuardResult validate(GuardPolicy policy, String payloadJson) {
        Long start = System.currentTimeMillis();
        try {
            if (String.isBlank(payloadJson)) {
                return GuardResult.block('SCHEMA', policy.policyName, policy.policyName, 'Payload JSON is empty');
            }

            Object parsed = JSON.deserializeUntyped(payloadJson);
            if (parsed == null) {
                return GuardResult.block(
                    'SCHEMA',
                    policy.policyName,
                    policy.policyName,
                    'Payload deserialized to null'
                );
            }

            if (String.isBlank(policy.schemaContractJson)) {
                return GuardResult.block(
                    'SCHEMA',
                    policy.policyName,
                    policy.policyName,
                    'No schema contract configured'
                );
            }

            Map<String, Object> contract = (Map<String, Object>) JSON.deserializeUntyped(policy.schemaContractJson);
            if (contract == null || !contract.containsKey('properties')) {
                return GuardResult.block(
                    'SCHEMA',
                    policy.policyName,
                    policy.policyName,
                    'Invalid schema contract: missing properties'
                );
            }

            Map<String, Object> properties = (Map<String, Object>) contract.get('properties');
            List<String> required = new List<String>();
            if (contract.containsKey('required')) {
                for (Object req : (List<Object>) contract.get('required')) {
                    required.add((String) req);
                }
            }

            List<Map<String, Object>> payloads = new List<Map<String, Object>>();
            if (parsed instanceof List<Object>) {
                for (Object item : (List<Object>) parsed) {
                    if (item instanceof Map<String, Object>) {
                        payloads.add((Map<String, Object>) item);
                    } else {
                        return GuardResult.block(
                            'SCHEMA',
                            policy.policyName,
                            policy.policyName,
                            'Payload array contains non-object element'
                        );
                    }
                }
            } else if (parsed instanceof Map<String, Object>) {
                payloads.add((Map<String, Object>) parsed);
            } else {
                return GuardResult.block(
                    'SCHEMA',
                    policy.policyName,
                    policy.policyName,
                    'Payload must be an object or array of objects'
                );
            }

            for (Map<String, Object> payload : payloads) {
                GuardResult check = validateSingle(payload, properties, required, policy.policyName);
                if (!check.isAllowed) {
                    return check;
                }
            }

            return GuardResult.allow(policy.policyName, policy.policyName);
        } catch (JSONException e) {
            return GuardResult.block(
                'SCHEMA',
                policy.policyName,
                policy.policyName,
                'Malformed JSON: ' + e.getMessage()
            );
        } catch (Exception e) {
            return GuardResult.block(
                'SCHEMA',
                policy.policyName,
                policy.policyName,
                'Validation error: ' + e.getMessage()
            );
        }
    }

    private static GuardResult validateSingle(
        Map<String, Object> payload,
        Map<String, Object> properties,
        List<String> required,
        String policyName
    ) {
        for (String key : payload.keySet()) {
            if (!properties.containsKey(key)) {
                return GuardResult.block('SCHEMA', policyName, policyName, 'Unknown field: ' + key);
            }
        }

        for (String req : required) {
            if (!payload.containsKey(req)) {
                return GuardResult.block('SCHEMA', policyName, policyName, 'Missing required field: ' + req);
            }
        }

        for (String key : payload.keySet()) {
            Object expected = properties.get(key);
            Object actual = payload.get(key);
            if (expected instanceof Map<String, Object>) {
                GuardResult typeCheck = validateType(key, actual, (Map<String, Object>) expected, policyName);
                if (!typeCheck.isAllowed) {
                    return typeCheck;
                }
            }
        }

        return GuardResult.allow(policyName, policyName);
    }

    private static GuardResult validateType(
        String fieldName,
        Object actual,
        Map<String, Object> expected,
        String policyName
    ) {
        String type = (String) expected.get('type');
        if (type == null) {
            return GuardResult.allow(policyName, policyName);
        }

        if (actual == null) {
            Boolean nullable = expected.containsKey('nullable') ? (Boolean) expected.get('nullable') : false;
            if (!nullable) {
                return GuardResult.block('SCHEMA', policyName, policyName, 'Field ' + fieldName + ' cannot be null');
            }
            return GuardResult.allow(policyName, policyName);
        }

        switch on type.toUpperCase() {
            when 'STRING' {
                if (!(actual instanceof String)) {
                    return GuardResult.block(
                        'SCHEMA',
                        policyName,
                        policyName,
                        'Field ' + fieldName + ' must be a string'
                    );
                }
                if (expected.containsKey('enum')) {
                    List<Object> enumValues = (List<Object>) expected.get('enum');
                    if (!enumValues.contains(actual)) {
                        return GuardResult.block(
                            'SCHEMA',
                            policyName,
                            policyName,
                            'Field ' + fieldName + ' value not in allowed enum'
                        );
                    }
                }
            }
            when 'INTEGER', 'NUMBER' {
                if (!(actual instanceof Integer) && !(actual instanceof Double) && !(actual instanceof Long)) {
                    return GuardResult.block(
                        'SCHEMA',
                        policyName,
                        policyName,
                        'Field ' + fieldName + ' must be a number'
                    );
                }
                if (expected.containsKey('minimum')) {
                    Double min = (Double) expected.get('minimum');
                    Double val = actual instanceof Integer
                        ? (Double) actual
                        : (actual instanceof Long ? (Double) actual : (Double) actual);
                    if (val < min) {
                        return GuardResult.block(
                            'SCHEMA',
                            policyName,
                            policyName,
                            'Field ' + fieldName + ' below minimum'
                        );
                    }
                }
                if (expected.containsKey('maximum')) {
                    Double max = (Double) expected.get('maximum');
                    Double val = actual instanceof Integer
                        ? (Double) actual
                        : (actual instanceof Long ? (Double) actual : (Double) actual);
                    if (val > max) {
                        return GuardResult.block(
                            'SCHEMA',
                            policyName,
                            policyName,
                            'Field ' + fieldName + ' above maximum'
                        );
                    }
                }
            }
            when 'BOOLEAN' {
                if (!(actual instanceof Boolean)) {
                    return GuardResult.block(
                        'SCHEMA',
                        policyName,
                        policyName,
                        'Field ' + fieldName + ' must be a boolean'
                    );
                }
            }
            when 'ARRAY' {
                if (!(actual instanceof List<Object>)) {
                    return GuardResult.block(
                        'SCHEMA',
                        policyName,
                        policyName,
                        'Field ' + fieldName + ' must be an array'
                    );
                }
            }
            when 'OBJECT' {
                if (!(actual instanceof Map<String, Object>)) {
                    return GuardResult.block(
                        'SCHEMA',
                        policyName,
                        policyName,
                        'Field ' + fieldName + ' must be an object'
                    );
                }
            }
            when else {
                return GuardResult.block('SCHEMA', policyName, policyName, 'Unsupported schema type: ' + type);
            }
        }

        return GuardResult.allow(policyName, policyName);
    }
}
