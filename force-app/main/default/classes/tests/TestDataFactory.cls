/**
 * TestDataFactory
 * ------------------------------------------------------------------
 * Centralized fixture creation for every AgentGuard test class
 * (blueprint Section 12.3). Builds records identically across suites
 * so a failure always points at the class under test, never at
 * divergent fixtures.
 *
 * Security note: creates synthetic fixtures only — no real org data
 * (RULES.md #9). Test users get globally-unique generated usernames.
 * ------------------------------------------------------------------
 */
@isTest
public inherited sharing class TestDataFactory {
    /**
     * @description Inserts a user under the named profile with a unique username.
     * @param alias Short alias (max 8 chars; truncated if longer).
     * @param profileName Profile API name, e.g. 'Read Only' or 'Standard User'.
     * @return Inserted User.
     */
    public static User createUser(String alias, String profileName) {
        String safeAlias = alias == null ? 'aguser' : alias.substring(0, Math.min(alias.length(), 8));
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String username = 'agentguard-' + safeAlias + '-' + System.currentTimeMillis() + '@example.invalid';
        User u = new User(
            Alias = safeAlias,
            Email = username,
            UserName = username,
            FirstName = 'AgentGuard',
            LastName = safeAlias.capitalize(),
            NickName = safeAlias,
            ProfileId = p.Id,
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            TimeZoneIdKey = 'America/Los_Angeles'
        );
        insert u;
        return u;
    }

    /**
     * @description Inserts one Account owned by the running user.
     * @param name Account Name value.
     * @return Inserted Account (Id populated).
     */
    public static Account createAccount(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    /**
     * @description Bulk-inserts Accounts with prefixed names, 200-safe.
     * @param prefix Name prefix per account.
     * @param count Number of accounts to insert.
     * @return Inserted accounts (Ids populated).
     */
    public static List<Account> createAccounts(String prefix, Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = prefix + ' ' + i));
        }
        insert accounts;
        return accounts;
    }

    /**
     * @description Registers a policy override for the scope of the current test.
     * @param policy Configured GuardPolicy to register.
     */
    public static void registerPolicy(GuardPolicy policy) {
        PolicyRegistry.registerForTesting(policy);
    }

    /**
     * @description Drops all registered policy overrides.
     */
    public static void clearPolicies() {
        PolicyRegistry.clearForTesting();
    }
}
