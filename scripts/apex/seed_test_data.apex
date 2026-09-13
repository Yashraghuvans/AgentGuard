// seed_test_data.apex - scratch-org data seeding for flow/integration tests.
//
// Deploys Guard_Policy__mdt records and creates test users with scoped
// permission sets for restricted FLS profiles. CI invokes this via:
//   sf apex run --file scripts/apex/seed_test_data.apex --target-org flow-org

// Create the UpdateAccountTerritory policy
Guard_Policy__mdt territoryPolicy = new Guard_Policy__mdt(
  DeveloperName = 'UpdateAccountTerritory',
  Label = 'Update Account Territory',
  IsActive__c = true,
  TargetSObjectType__c = 'Account',
  Operation__c = 'MODIFY',
  SchemaContract__c = '{"properties": {"AccountId": {"type": "string", "required": true}, "Territory__c": {"type": "string"}}, "required": ["AccountId"]}',
  MaxRecordsPerCall__c = 5,
  RateLimitPerMinute__c = 10,
  RateLimitWindowSeconds__c = 60,
  AllowedProfiles__c = '',
  AllowedPermissionSets__c = ''
);
insert territoryPolicy;

// Create RateLimitedAction policy
Guard_Policy__mdt ratePolicy = new Guard_Policy__mdt(
  DeveloperName = 'RateLimitedAction',
  Label = 'Rate Limited Action',
  IsActive__c = true,
  TargetSObjectType__c = 'Account',
  Operation__c = 'MODIFY',
  SchemaContract__c = '{"properties": {"AccountId": {"type": "string"}}, "required": ["AccountId"]}',
  MaxRecordsPerCall__c = 1,
  RateLimitPerMinute__c = 3,
  RateLimitWindowSeconds__c = 60,
  AllowedProfiles__c = '',
  AllowedPermissionSets__c = ''
);
insert ratePolicy;

// Create AuditTestAction policy
Guard_Policy__mdt auditPolicy = new Guard_Policy__mdt(
  DeveloperName = 'AuditTestAction',
  Label = 'Audit Test Action',
  IsActive__c = true,
  TargetSObjectType__c = 'Account',
  Operation__c = 'MODIFY',
  SchemaContract__c = '{"properties": {"AccountId": {"type": "string"}}, "required": ["AccountId"]}',
  MaxRecordsPerCall__c = 1,
  RateLimitPerMinute__c = 10,
  RateLimitWindowSeconds__c = 60,
  AllowedProfiles__c = '',
  AllowedPermissionSets__c = ''
);
insert auditPolicy;

// Create AuditBlockTest policy
Guard_Policy__mdt auditBlockPolicy = new Guard_Policy__mdt(
  DeveloperName = 'AuditBlockTest',
  Label = 'Audit Block Test',
  IsActive__c = true,
  TargetSObjectType__c = 'Account',
  Operation__c = 'MODIFY',
  SchemaContract__c = '{"properties": {"AccountId": {"type": "string"}}, "required": ["AccountId"]}',
  MaxRecordsPerCall__c = 1,
  RateLimitPerMinute__c = 10,
  RateLimitWindowSeconds__c = 60,
  AllowedProfiles__c = '',
  AllowedPermissionSets__c = ''
);
insert auditBlockPolicy;

// Create test users for restricted access scenarios
Profile readOnlyProfile = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
User restrictedUser = new User(
  Alias = 'agtfrest',
  Email = 'agentguard-flow-restricted-' + System.currentTimeMillis() + '@example.invalid',
  UserName = 'agentguard-flow-restricted-' + System.currentTimeMillis() + '@example.invalid',
  FirstName = 'AgentGuard',
  LastName = 'Restricted',
  NickName = 'agtfrest',
  ProfileId = readOnlyProfile.Id,
  LocaleSidKey = 'en_US',
  LanguageLocaleKey = 'en_US',
  EmailEncodingKey = 'UTF-8',
  TimeZoneIdKey = 'America/Los_Angeles'
);
insert restrictedUser;

System.debug('seed_test_data.apex: Guard_Policy__mdt records and test users created.');
