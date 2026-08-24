// seed_test_data.apex - scratch-org data seeding for flow/integration tests.
//
// STATUS: placeholder. Populates Guard_Policy__mdt records and test accounts
// when the policy metadata type ships at v0.1/v0.6 (roadmap). CI invokes this
// via: sf apex run --file scripts/apex/seed_test_data.apex
//
// Planned contents:
//   Deploy default restrictive Guard_Policy__mdt records for example actions
//   Create test users with scoped permission sets (restricted FLS profiles)
//   Seed Account/Contact fixtures owned by low-privilege test users
System.debug('seed_test_data.apex: no-op until core gate code ships (v0.1).');
