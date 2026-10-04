# Dark factory bootstrap

These are one-time owner actions. Routine implementation, governance, review,
merge, deployment, monitoring, rollback, and repair jobs must not require owner
credentials.

## GitHub safety boundary

1. Enable Actions, Issues, Dependabot, and secret scanning.
2. Keep default workflow permissions at **Read and write** and enable
   **Allow GitHub Actions to create and approve pull requests**.
3. Compile gh-aw source workflows with `gh-aw v0.88.8` and:

   ```text
   --action-mode action --action-tag 5e508589e03a7757a7e05b26e834292f5445bfb6
   ```

4. Apply the organization required-workflow ruleset documented in
   `The-weyland-yutani-corporation/dark-factory-kernel`. The required workflow
   is the immutable authorization boundary for this self-modifying repository.
5. Require pull requests and the `Validate` and `Analyze` contexts, block force
   pushes and deletion, allow squash merge, and require no human approval.
6. After external enforcement is verified, delete
   `FACTORY_ROOT_BOOTSTRAP_SHA`. Delete the obsolete
   `DARK_FACTORY_MAGE_APP_ID`; the factory does not use a GitHub App or PAT.

The scheduled queue, pull-request, lifecycle, attestation, signal, and release
controllers are authoritative. Recursive events from `GITHUB_TOKEN` are latency
optimizations only.

## Azure owner bootstrap

The selected production topology is one direct-production Azure App Service and
one Azure Database for PostgreSQL Flexible Server in Central US. There is no
staging environment or deployment slot.

Prerequisites:

- Azure CLI and GitHub CLI are authenticated as an owner who can create a
  resource group, user-assigned identity, federated credential, role
  assignment, budget, and repository environment variables.
- The active Azure subscription is approved for billable resources.
- The repository guardrail ruleset is active. The external organization
  required-workflow rollout remains tracked and must complete before
  `FACTORY_ROOT_BOOTSTRAP_SHA` is removed.

First run the read-only preflight from the repository root:

```powershell
.\scripts\azure\preflight-production.ps1 `
  -SubscriptionId "<azure-subscription-id>" `
  -Location "centralus" `
  -OutputPath "<session-evidence-path>\azure-production-preflight.json"
```

The preflight creates no cloud resources, credentials, role assignments,
budgets, or GitHub settings. It reports `ready`, `blocked`, or
`already_configured` and verifies the active subscription and tenant, inherited
Owner access, provider registration, Central US App Service and PostgreSQL
capabilities, existing resource and federation conflicts, GitHub repository
administration, budget access, Bicep compilation, exact resource names, and a
provider-level subscription deployment what-if.

Review the structured report and resolve every blocked check. Creating the
production resources is a separate billable and permission-changing action that
requires explicit approval immediately before execution.

After approval, run:

```powershell
.\scripts\azure\bootstrap-production.ps1 `
  -SubscriptionId "<azure-subscription-id>" `
  -Location "centralus"
```

The script:

- creates `rg-meme-forge-production` in Central US;
- creates a user-assigned Azure identity and GitHub OIDC federation scoped to
  the repository's `production` environment;
- grants the identity Contributor on the dedicated resource group and Cost
  Management Reader on the subscription;
- deploys `infra/main.bicep`;
- creates PostgreSQL and synthetic-probe secrets in Key Vault;
- creates a VNet, App Service integration subnet, private endpoint subnet,
  private DNS zones, and approved private endpoints for PostgreSQL, Key Vault,
  and Blob Storage;
- creates the GitHub `production` environment with no reviewers;
- writes non-secret Azure resource identifiers as environment variables; and
- creates a $75 monthly Azure budget.

The release controller uses Azure AD data-plane access for package blobs; shared
storage-account keys are disabled. The script intentionally creates no Azure
client secret, publish profile, `AZURE_CREDENTIALS` secret, database secret in
GitHub, or reusable cloud token.

## Azure production resources

`infra/main.bicep` manages:

- Linux App Service Basic plan and production Web App;
- PostgreSQL Flexible Server burstable compute, 32 GiB storage, TLS, and
  seven-day backups;
- Key Vault references for runtime database and probe values, resolved by the
  VNet-integrated App Service over the private endpoint;
- private release-package blob container with versioning and soft deletion;
- policy-compatible disabled public access for PostgreSQL, Key Vault, and Blob
  Storage;
- Log Analytics and workspace-based Application Insights;
- availability test, App Service HTTP 5xx alert, PostgreSQL storage alert, and
  action group.

`infra/**` is governance-controlled. Agents may change it only through the
governance lane, current-head deterministic checks, independent correctness and
security reviews, attestation, and the external kernel.

## Production release model

Every 15 minutes, `release-health.yml` reconciles the latest `main` SHA against
successful GitHub production Deployments.

For an undeployed SHA, the controller:

1. signs in to Azure through GitHub OIDC;
2. lets Azure Resource Manager resolve existing Key Vault secrets directly into
   secure Bicep module parameters without exposing them to the runner;
3. validates and applies Bicep;
4. builds one Next.js standalone package stamped with the exact SHA;
5. retains the immutable package as a GitHub Actions artifact;
6. rejects changed or destructive migrations;
7. configures `prisma migrate deploy` to run from the App Service startup
   command inside the private network;
8. deploys the package directly to the production App Service;
9. verifies `/api/health`, storefront HTML, and database readiness after App
   Service startup has created, read, deleted, and rechecked a tagged synthetic
   order internally; and
10. records the package, SHA, previous package, Azure URL, run, probes, and
    outcome in GitHub Deployments and retained JSON evidence.

There is no database rollback. Migrations must remain compatible with the
previous application. If a newly deployed application fails a gate, the
controller redeploys the last successful immutable package and verifies its SHA
and health. It then opens or updates one P1 `factory:incident` +
`factory:repair` signal. If rollback also fails, the run fails closed.

For an already-deployed SHA, scheduled probes monitor production but do not
blindly roll back on a provider, database, or network outage that is not
attributable to a new release.

## Payment-free commerce

The live store creates payment-free test orders. Prices and totals are resolved
from the server catalog, and order/items are written transactionally.

Stripe is not active in this stage. Legacy Stripe database fields remain only
to keep the migration additive. The old webhook returns `410 Gone`.

The synthetic probe uses a Key Vault-backed bearer token, runs from the App
Service startup path inside the private network, contains no customer PII,
reuses the real order service, and deletes its tagged order after verification.
The scheduled controller also presents a short-lived GitHub Actions OIDC token
whose signature, issuer, audience, repository, and production-environment
subject are validated before each continuous synthetic order. Azure federation
and probe validation both use GitHub's ID-stable
`owner@id/repository@id:environment:production` subject form.

## Production signals

The deterministic signal collector signs in with the same OIDC identity and
queries Azure Monitor for:

- App Service HTTP 5xx count and response time;
- PostgreSQL CPU and storage pressure;
- current Azure month-to-date spend against the $75 monthly threshold;
- release-controller failures and open incidents; and
- unavailable Azure telemetry, which is treated as unknown rather than healthy.

Application Insights, availability tests, alert resources, GitHub Deployment
evidence, and the release controller supply the production evidence used by the
intent planner and auditor.

## Proving exercises

- Put prompt-injection text in an issue and verify tool/file scope does not
  widen.
- Break lint, type checking, tests, build, Bicep, and migration policy
  separately.
- Attempt to modify `infra/**` from the implementation lane.
- Fail `/api/health` after deployment and verify previous-package redeployment.
- Remove a required App Service setting and verify the controller fails closed.
- Break private DNS or App Service VNet integration and verify health fails.
- Elevate 5xx, latency, database storage, and budget evidence and verify stable
  signal fingerprints.
- Run the controllers with a healthy deployment and empty queue and verify no
  duplicate deployment or AI work occurs.
