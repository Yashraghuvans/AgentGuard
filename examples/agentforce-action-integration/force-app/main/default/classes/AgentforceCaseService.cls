/**
 * AgentforceCaseService
 * ------------------------------------------------------------------
 * Example Agentforce action for creating/updating Cases.
 * Designed to be registered as an Agentforce action (via Agent Builder
 * or Agentforce metadata) and wrapped with AgentGuard.wrap().
 *
 * This action is scoped to the 'Agentforce Service Agent' profile via
 * Guard_Policy__mdt, ensuring only authorized agents can invoke it.
 */
public inherited sharing class AgentforceCaseService {
    public class Request {
        @InvocableVariable(label='Subject' required=true)
        public String Subject;

        @InvocableVariable(label='Description' required=false)
        public String Description;

        @InvocableVariable(label='Origin' required=false)
        public String Origin;

        @InvocableVariable(label='Priority' required=false)
        public String Priority;

        @InvocableVariable(label='AccountId' required=false)
        public String AccountId;

        @InvocableVariable(label='ContactId' required=false)
        public String ContactId;

        public Request() {
        }

        public Request(String subject) {
            this.Subject = subject;
        }
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='CaseId')
        public String caseId;

        @InvocableVariable(label='Error')
        public String error;

        public Result(Boolean success, String caseId, String error) {
            this.success = success;
            this.caseId = caseId;
            this.error = error;
        }
    }

    /**
     * Invocable entry point for Agentforce action.
     * Wrapped with AgentGuard for full enforcement.
     */
    @InvocableMethod(label='Create Case' description='Creates a new Case with AgentGuard enforcement')
    public static List<Result> createCase(List<Request> requests) {
        GuardResult check = AgentGuard.wrap('AgentforceCreateCase', JSON.serialize(requests));
        if (!check.isAllowed) {
            throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            try {
                Case c = new Case(
                    Subject = req.Subject,
                    Description = req.Description,
                    Origin = req.Origin != null ? req.Origin : 'Agent',
                    Priority = req.Priority != null ? req.Priority : 'Medium'
                );
                if (req.AccountId != null)
                    c.AccountId = req.AccountId;
                if (req.ContactId != null)
                    c.ContactId = req.ContactId;

                insert c;
                results.add(new Result(true, c.Id, null));
            } catch (Exception e) {
                throw e; // Rollback via AgentGuard savepoint
            }
        }
        return results;
    }

    @InvocableMethod(label='Update Case' description='Updates an existing Case with AgentGuard enforcement')
    public static List<Result> updateCase(List<Request> requests) {
        GuardResult check = AgentGuard.wrap('AgentforceUpdateCase', JSON.serialize(requests));
        if (!check.isAllowed) {
            throw new AgentGuard.BlockedException(check.reason, check.decision, check.gateName);
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            try {
                // Expect CaseId in Subject field for update (simplified for example)
                Case c = [SELECT Id FROM Case WHERE Id = :req.Subject LIMIT 1];
                if (req.Description != null)
                    c.Description = req.Description;
                if (req.Priority != null)
                    c.Priority = req.Priority;
                if (req.Origin != null)
                    c.Origin = req.Origin;

                update c;
                results.add(new Result(true, c.Id, null));
            } catch (Exception e) {
                throw e;
            }
        }
        return results;
    }
}
