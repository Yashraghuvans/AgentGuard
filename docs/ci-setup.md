# CI Setup — Dev Hub JWT Auth & Branch Protection

One-time repository configuration so `ci.yml` runs end to end. Tracked as
[issue #1](https://github.com/Yashraghuvans/AgentGuard/issues/1). Follow the
steps in order; each has a verification at the end.

## 1. Create the Dev Hub org (free)

1. Sign up at <https://developer.salesforce.com/signup> (Developer Edition,
   free forever) or use a Trailhead Playground.
2. In the org: **Setup → Quick Find → "Dev Hub"**:
   - **Enable Dev Hub** = On
   - **Enable Unlocked Packages and Second-Generation Managed Packages** = On
     (required for the 2GP release pipeline)
   - Leave scratch orgs enabled (default limits apply on free tier).

Verify locally:

```bash
sf org login web --alias devhub
sf org list   # devhub shows a DEV HUB badge
```

## 2. Generate the certificate + private key

```bash
bash scripts/ci/setup-jwt-auth.sh .   # creates ./server.crt and ./server.key
```

`server.key` is already git-ignored — never move it into tracked paths.

## 3. Create the JWT connected app

In the **Dev Hub org**: **Setup → App Manager → New Connected App (classic)**

| Field                  | Value                                    |
| ---------------------- | ---------------------------------------- |
| Callback URL           | `http://localhost:1717`                  |
| Use digital signatures | upload `server.crt`                      |
| OAuth Scopes           | `api`, `refresh_token`, `offline_access` |

After saving, copy the **Consumer Key**. If OAuth policy blocks the first JWT
attempt, approve via **Manage Connected Apps → Edit Policies** (admin pre-
approval), or run one interactive `sf org login jwt` and click Continue.

## 4. Add GitHub secrets and activate the CI org jobs

Repository → **Settings → Secrets and variables → Actions**:

| Type     | Name             | Value                         |
| -------- | ---------------- | ----------------------------- |
| Secret   | `SF_JWT_KEY`     | full contents of `server.key` |
| Secret   | `SF_CLIENT_ID`   | connected app Consumer Key    |
| Secret   | `SF_DEVHUB_USER` | Dev Hub login username        |
| Variable | `SF_CI_ENABLED`  | `true`                        |

The two scratch-org jobs (`unit-tests`, `flow-integration-tests`) are gated on
`vars.SF_CI_ENABLED == 'true'` so pull requests stay green before this step is
done — they activate automatically once the variable exists.

## 5. Branch protection rules

Repository → **Settings → Branches → Add branch protection rule** for `main`:

- [ ] Require a pull request before merging
- [ ] Require status checks: **Lint & Static Analysis**, **Unit Tests (scratch
      org)**, **Flow / Integration Tests (scratch org)** — add these after the
      first PR runs so the check names exist to select
      (until `SF_CI_ENABLED=true` is set, only the lint job will appear)
- [ ] Require branches to be up to date before merging
- [ ] Include administrators (RULES.md #1: no exceptions, including maintainer)

`sec/*` second-review expectations are process rules documented in
[GOVERNANCE.md](../GOVERNANCE.md); GitHub cannot enforce reviewer identity on a
solo project — record the double-read trace in the PR body per that protocol.

## Verification

Open a trivial PR touching any file:

- Before Step 4: `Lint & Static Analysis` green; org jobs show _Skipped_.
- After Step 4: all three jobs green, scratch org created/deleted in logs.

Tick the remaining boxes on issue #1 when done.
