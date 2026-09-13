/**
 * TerritoryService
 * ------------------------------------------------------------------
 * Example invocable action for updating Account territories.
 * Wrapped with AgentGuard.wrap() for schema validation, CRUD/FLS
 * enforcement, rate limiting, transactional rollback, and audit logging.
 */
public inherited sharing class TerritoryService {
    public class Request {
        @InvocableVariable(label='Account Id' required=true)
        public String AccountId;

        @InvocableVariable(label='Territory' required=false)
        public String Territory__c;

        @InvocableVariable(label='Status' required=false)
        public String Status__c;

        public Request() {
        }

        public Request(String accountId, String territory) {
            this.AccountId = accountId;
            this.Territory__c = territory;
        }

        public Request(String accountId, String territory, String status) {
            this.AccountId = accountId;
            this.Territory__c = territory;
            this.Status__c = status;
        }
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Account Id')
        public String accountId;

        @InvocableVariable(label='Error')
        public String error;

        public Result(Boolean success, String accountId, String error) {
            this.success = success;
            this.accountId = accountId;
            this.error = error;
        }
    }

    /**
     * Invocable entry point. Wrapped with AgentGuard for full enforcement.
     */
    @InvocableMethod(
        label='Update Account Territory'
        description='Reassigns Account territory with full AgentGuard enforcement'
    )
    public static List<Result> execute(List<Request> requests) {
        // Single line: wrap validates, checks access, rate limits, opens savepoint, audits
        GuardResult check = AgentGuard.wrap('UpdateAccountTerritory', JSON.serialize(requests));
        if (!check.isAllowed) {
            throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
        }

        // Business logic runs with savepoint already open
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            try {
                Account acc = [SELECT Id, Territory__c FROM Account WHERE Id = :req.AccountId LIMIT 1];
                acc.Territory__c = req.Territory__c;
                if (req.Status__c != null) {
                    acc.Status__c = req.Status__c;
                }
                update acc;
                results.add(new Result(true, req.AccountId, null));
            } catch (Exception e) {
                // Rollback handled by AgentGuard wrapper via savepoint
                throw e;
            }
        }
        return results;
    }
}
