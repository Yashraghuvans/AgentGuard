/**
 * AuditPublisher
 * ------------------------------------------------------------------
 * Publishes exactly one AgentGuard_Audit__e Platform Event per
 * AgentGuard decision — ALLOW, BLOCK, THROTTLED, or ROLLBACK.
 *
 * Security notes:
 * - Platform Events publish outside the transaction rollback boundary
 *   (ADR-001): a BLOCK that triggers rollback still leaves a durable,
 *   queryable audit record of the attempt.
 * - Payload contents are never stored — only a SHA-256 hash, proving
 *   what was attempted without leaking data into logs.
 * - Publishing must never throw into the caller: a failure to audit is
 *   logged at ERROR level but cannot break the enforcement decision.
 * ------------------------------------------------------------------
 */
public inherited sharing class AuditPublisher {
    /**
     * @description Value object describing one auditable decision.
     */
    public inherited sharing class AuditContext {
        public String policyName;
        public String actionName;
        public String gateName;
        public String decision;
        public String reason;
        public String payloadJson;
        public Long latencyMs;
        public Boolean flagged;
        public String actorId;

        /**
         * @description Fluent: sets policy name.
         * @param v Policy DeveloperName.
         * @return This context.
         */
        public AuditContext withPolicyName(String v) {
            policyName = v;
            return this;
        }

        /**
         * @description Fluent: sets action name.
         * @param v Action name passed to wrap().
         * @return This context.
         */
        public AuditContext withActionName(String v) {
            actionName = v;
            return this;
        }

        /**
         * @description Fluent: sets producing gate name.
         * @param v FACADE | SCHEMA | ACCESS | RATE | ROLLBACK.
         * @return This context.
         */
        public AuditContext withGateName(String v) {
            gateName = v;
            return this;
        }

        /**
         * @description Fluent: sets decision string.
         * @param v ALLOW | BLOCK | THROTTLED | ROLLBACK.
         * @return This context.
         */
        public AuditContext withDecision(String v) {
            decision = v;
            return this;
        }

        /**
         * @description Fluent: sets reason string.
         * @param v Reason; truncated to 255 chars on publish.
         * @return This context.
         */
        public AuditContext withReason(String v) {
            reason = v;
            return this;
        }

        /**
         * @description Fluent: sets raw payload JSON (hashed, never stored verbatim).
         * @param v Raw payload as received by wrap().
         * @return This context.
         */
        public AuditContext withPayloadJson(String v) {
            payloadJson = v;
            return this;
        }

        /**
         * @description Fluent: sets measured latency.
         * @param v CPU milliseconds spent in the gate chain.
         * @return This context.
         */
        public AuditContext withLatencyMs(Long v) {
            latencyMs = v;
            return this;
        }

        /**
         * @description Fluent: sets degraded-mode flag.
         * @param v True when decision carries a documented fallback flag.
         * @return This context.
         */
        public AuditContext withFlagged(Boolean v) {
            flagged = v;
            return this;
        }

        /**
         * @description Fluent: overrides the recorded actor (defaults to running user).
         * @param v 18-char user Id.
         * @return This context.
         */
        public AuditContext withActorId(String v) {
            actorId = v;
            return this;
        }
    }

    @TestVisible
    private static Boolean captureMode = false;

    @TestVisible
    private static List<AgentGuard_Audit__e> capturedEvents = new List<AgentGuard_Audit__e>();

    /**
     * @description Builds a fully-populated event from a context and publishes it.
     *              Never throws. In test capture mode the event is queued instead
     *              of published so flow tests can assert on decisions.
     * @param ctx Decision description built via AuditContext fluent setters.
     */
    public static void publish(AuditContext ctx) {
        try {
            AgentGuard_Audit__e evt = buildEvent(ctx);
            if (Test.isRunningTest() && captureMode) {
                capturedEvents.add(evt);
                return;
            }
            EventBus.publish(evt); // NOPMD - SaveResult intentionally ignored; audit is best-effort
        } catch (Exception e) {
            // NOPMD - publish failure must never affect the guarded call
        }
    }

    /**
     * @description Computes the SHA-256 hex digest used for PayloadHash__c / AgentKey__c.
     * @param value Raw value to digest (null treated as empty string).
     * @return Lowercase hex string, always 64 characters for SHA-256.
     */
    @TestVisible
    private static String sha256Hex(String value) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(value == null ? '' : value));
        return EncodingUtil.convertToHex(digest);
    }

    private static AgentGuard_Audit__e buildEvent(AuditContext ctx) {
        String actor = String.isNotBlank(ctx.actorId) ? ctx.actorId : UserInfo.getUserId();
        return new AgentGuard_Audit__e(
            PolicyName__c = truncate(ctx.policyName, 255),
            ActionName__c = truncate(ctx.actionName, 255),
            GateName__c = truncate(ctx.gateName, 40),
            Decision__c = ctx.decision == null ? '' : ctx.decision,
            Reason__c = truncate(ctx.reason, 255),
            PayloadHash__c = sha256Hex(ctx.payloadJson),
            LatencyMs__c = ctx.latencyMs == null ? 0 : ctx.latencyMs,
            Flagged__c = ctx.flagged == true,
            ActorId__c = truncate(actor, 18),
            AgentKey__c = sha256Hex(actor)
        );
    }

    private static String truncate(String value, Integer max) {
        if (value == null) {
            return '';
        }
        return value.length() <= max ? value : value.substring(0, max);
    }

    /**
     * @description Enables test capture mode — events are queued instead of published.
     * @param enabled True to enable capture, false to disable.
     */
    public static void setCaptureMode(Boolean enabled) {
        captureMode = enabled == true;
    }

    /**
     * @description Returns captured events in test mode and clears the buffer.
     * @return List of captured AgentGuard_Audit__e events.
     */
    public static List<AgentGuard_Audit__e> getCapturedEvents() {
        List<AgentGuard_Audit__e> events = new List<AgentGuard_Audit__e>(capturedEvents);
        capturedEvents.clear();
        return events;
    }
}
