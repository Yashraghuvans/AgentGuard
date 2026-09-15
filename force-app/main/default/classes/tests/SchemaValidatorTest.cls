/**
 * SchemaValidatorTest
 * ------------------------------------------------------------------
 * Unit tests for SchemaValidator gate. Positive path proves valid
 * payloads pass; negative path proves unknown keys, missing required
 * fields, and type mismatches are blocked.
 */
@isTest
private class SchemaValidatorTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createUser('agsch', 'Standard User');
    }

    private static GuardPolicy validPolicy() {
        String contract = '{"properties": {"AccountId": {"type": "string", "required": true}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}';
        return GuardPolicy.disabled('UpdateAccountTerritory').withEnabled(true).withSchemaContract(contract);
    }

    @isTest
    static void given_validPayload_when_validated_then_allows() {
        System.runAs(ctxUser()) {
            String payload = '{"AccountId": "001000000000001", "Territory__c": "West"}';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(true, r.isAllowed, 'Valid payload must be allowed');
        }
    }

    @isTest
    static void given_validArrayPayload_when_validated_then_allows() {
        System.runAs(ctxUser()) {
            String payload = '[{"AccountId": "001000000000001", "Territory__c": "West"}, {"AccountId": "001000000000002", "Territory__c": "East"}]';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(true, r.isAllowed, 'Valid array payload must be allowed');
        }
    }

    @isTest
    static void given_missingRequiredField_when_validated_then_blocksWithReason() {
        System.runAs(ctxUser()) {
            String payload = '{"Territory__c": "West"}';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(false, r.isAllowed, 'Missing required must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
            System.assert(r.reason.contains('Missing required field'), 'Reason must name the field');
        }
    }

    @isTest
    static void given_unknownField_when_validated_then_blocksWithReason() {
        System.runAs(ctxUser()) {
            String payload = '{"AccountId": "001000000000001", "UnknownField__c": "Bad"}';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(false, r.isAllowed, 'Unknown field must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
            System.assert(r.reason.contains('Unknown field'), 'Reason must name the field');
        }
    }

    @isTest
    static void given_wrongType_when_validated_then_blocksWithReason() {
        System.runAs(ctxUser()) {
            String payload = '{"AccountId": 12345, "Territory__c": "West"}';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(false, r.isAllowed, 'Wrong type must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
            System.assert(r.reason.contains('must be a string'), 'Reason must explain type mismatch');
        }
    }

    @isTest
    static void given_malformedJson_when_validated_then_blocksWithReason() {
        System.runAs(ctxUser()) {
            String payload = '{not valid json';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(false, r.isAllowed, 'Malformed JSON must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
            System.assert(r.reason.contains('Malformed JSON'), 'Reason must indicate parse error');
        }
    }

    @isTest
    static void given_emptyPayload_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            GuardResult r = SchemaValidator.validate(validPolicy(), '');

            System.assertEquals(false, r.isAllowed, 'Empty payload must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
        }
    }

    @isTest
    static void given_noSchemaContract_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true);
            GuardResult r = SchemaValidator.validate(policy, '{"foo": "bar"}');

            System.assertEquals(false, r.isAllowed, 'No schema contract must block');
            System.assertEquals('SCHEMA', r.gateName, 'Must be SCHEMA gate');
        }
    }

    @isTest
    static void given_integerRangeValidation_when_outOfBounds_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Count__c": {"type": "integer", "minimum": 1, "maximum": 100}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Count__c": 0}');
            System.assertEquals(false, r.isAllowed, 'Below minimum must block');

            r = SchemaValidator.validate(policy, '{"Count__c": 101}');
            System.assertEquals(false, r.isAllowed, 'Above maximum must block');
        }
    }

    @isTest
    static void given_enumValidation_when_invalidValue_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Status__c": {"type": "string", "enum": ["Active", "Inactive"]}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Status__c": "Invalid"}');
            System.assertEquals(false, r.isAllowed, 'Invalid enum must block');
        }
    }

    @isTest
    static void given_nullableFieldWithNull_when_validated_then_allows() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Optional__c": {"type": "string", "nullable": true}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Optional__c": null}');
            System.assertEquals(true, r.isAllowed, 'Nullable null must allow');
        }
    }

    @isTest
    static void given_nonNullableFieldWithNull_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Required__c": {"type": "string"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Required__c": null}');
            System.assertEquals(false, r.isAllowed, 'Non-nullable null must block');
        }
    }

    @isTest
    static void given_arrayTypeValidation_when_validArray_then_allows() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Tags__c": {"type": "array"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Tags__c": ["tag1", "tag2"]}');
            System.assertEquals(true, r.isAllowed, 'Valid array must allow');
        }
    }

    @isTest
    static void given_arrayTypeValidation_when_notArray_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Tags__c": {"type": "array"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Tags__c": "not_an_array"}');
            System.assertEquals(false, r.isAllowed, 'Non-array must block');
            System.assert(r.reason.contains('must be an array'), 'Reason must explain type mismatch');
        }
    }

    @isTest
    static void given_objectTypeValidation_when_validObject_then_allows() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Meta__c": {"type": "object"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Meta__c": {"key": "value"}}');
            System.assertEquals(true, r.isAllowed, 'Valid object must allow');
        }
    }

    @isTest
    static void given_objectTypeValidation_when_notObject_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Meta__c": {"type": "object"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Meta__c": "not_an_object"}');
            System.assertEquals(false, r.isAllowed, 'Non-object must block');
            System.assert(r.reason.contains('must be an object'), 'Reason must explain type mismatch');
        }
    }

    @isTest
    static void given_booleanTypeValidation_when_boolean_then_allows() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"IsActive__c": {"type": "boolean"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"IsActive__c": true}');
            System.assertEquals(true, r.isAllowed, 'Valid boolean must allow');
        }
    }

    @isTest
    static void given_booleanTypeValidation_when_notBoolean_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"IsActive__c": {"type": "boolean"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"IsActive__c": "yes"}');
            System.assertEquals(false, r.isAllowed, 'Non-boolean must block');
            System.assert(r.reason.contains('must be a boolean'), 'Reason must explain type mismatch');
        }
    }

    @isTest
    static void given_numberTypeValidation_when_number_then_allows() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Amount__c": {"type": "number"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r1 = SchemaValidator.validate(policy, '{"Amount__c": 42.5}');
            System.assertEquals(true, r1.isAllowed, 'Double must allow');

            GuardResult r2 = SchemaValidator.validate(policy, '{"Amount__c": 42}');
            System.assertEquals(true, r2.isAllowed, 'Integer must allow');
        }
    }

    @isTest
    static void given_numberTypeValidation_when_notNumber_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Amount__c": {"type": "number"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Amount__c": "forty-two"}');
            System.assertEquals(false, r.isAllowed, 'Non-number must block');
            System.assert(r.reason.contains('must be a number'), 'Reason must explain type mismatch');
        }
    }

    @isTest
    static void given_payloadDeserializesToNull_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            GuardResult r = SchemaValidator.validate(validPolicy(), 'null');
            System.assertEquals(false, r.isAllowed, 'Null deserialized payload must block');
            System.assert(r.reason.contains('deserialized to null'), 'Reason must explain null');
        }
    }

    @isTest
    static void given_invalidContractMissingProperties_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"wrongStructure": true}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"foo": "bar"}');
            System.assertEquals(false, r.isAllowed, 'Invalid contract must block');
            System.assert(r.reason.contains('missing properties'), 'Reason must explain bad contract');
        }
    }

    @isTest
    static void given_unsupportedSchemaType_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            String contract = '{"properties": {"Field__c": {"type": "unsupported_type"}}}';
            GuardPolicy policy = GuardPolicy.disabled('Test').withEnabled(true).withSchemaContract(contract);

            GuardResult r = SchemaValidator.validate(policy, '{"Field__c": "value"}');
            System.assertEquals(false, r.isAllowed, 'Unsupported type must block');
            System.assert(r.reason.contains('Unsupported schema type'), 'Reason must explain unsupported type');
        }
    }

    @isTest
    static void given_arrayWithNonObjectElement_when_validated_then_blocks() {
        System.runAs(ctxUser()) {
            String payload = '[{"AccountId": "001"}, "not_an_object"]';
            GuardResult r = SchemaValidator.validate(validPolicy(), payload);

            System.assertEquals(false, r.isAllowed, 'Array with non-object must block');
            System.assert(r.reason.contains('non-object element'), 'Reason must explain bad array element');
        }
    }

    private static User ctxUser() {
        return [SELECT Id FROM User WHERE Alias = 'agsch' LIMIT 1];
    }
}
