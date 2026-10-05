# Azure Deployment Plan

> **Status:** Deployed

Generated: 2026-10-04T13:16:56Z

---

## 1. Project Overview

**Goal:** Deploy the autonomous Meme Forge production stack and establish its GitHub OIDC release trust boundary.

**Path:** Add Components

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | Production |
| Scale | Small |
| Budget | Cost-Optimized, with a $75 monthly budget signal |
| Subscription | ME-MngEnvMCAP744360-sharmave-1 (`ad92e163-a85e-40cc-bb50-054b0b8197a8`) |
| Location | Central US (`centralus`) |

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Storefront and API | Frontend/API | Next.js 16, Node.js 22 | `src/` |
| Relational data | Database | Prisma, PostgreSQL 16 | `prisma/` |
| Production control | Release automation | GitHub Actions, Azure CLI, Bicep | `.github/workflows/release-health.yml` |
| Infrastructure | IaC | Bicep | `infra/` |
| Bootstrap and preflight | Operations | PowerShell, Azure CLI, GitHub CLI | `scripts/azure/` |

## 4. Recipe Selection

**Selected:** Bicep with repository bootstrap orchestration

**Rationale:** The approved production resource graph already exists in `infra/main.bicep`; `scripts/azure/bootstrap-production.ps1` adds the one-time identity, federation, scoped RBAC, GitHub environment variables, firewall reconciliation, and budget setup.

## 5. Architecture

**Stack:** Azure App Service direct production

### Service Mapping

| Component | Azure Service | SKU |
|-----------|---------------|-----|
| Next.js application | Linux App Service | Basic B1 |
| Relational database | PostgreSQL Flexible Server | Burstable `Standard_B1ms`, 32 GiB, zone 1 |
| Release packages | GitHub Actions artifacts | 90-day immutable retention |

### Supporting Services

| Service | Purpose |
|---------|---------|
| Log Analytics | Centralized production logs |
| Application Insights | APM and request/dependency telemetry |
| Virtual Network | App Service regional integration and private endpoint subnets |
| Private DNS | Private resolution for PostgreSQL, Key Vault, and Blob Storage |
| Key Vault | Authoritative database URL, administrator password, and synthetic probe token |
| Managed identities | GitHub OIDC deployment and App Service Key Vault access |
| Azure Monitor | Availability test, 5xx alert, PostgreSQL storage alert |
| Cost Management budget | $75 monthly production budget signal |

### Role Assignment Verification

- **Status:** Verified
- **GitHub OIDC identity:** Contributor on only `rg-meme-forge-production` for resource reconciliation and Cost Management Reader at subscription scope for production spend signals. New bootstraps do not assign Blob data-plane access.
- **App Service system identity:** Key Vault `get` access resolves runtime database and probe references over the private endpoint.
- **Bootstrap operator:** Existing inherited Owner access covers resource creation and scoped role assignment.
- **Long-lived credentials:** None. No client secret, publish profile, storage key, database secret, or reusable cloud token is stored in GitHub.

## 6. Provisioning Limit Checklist

| Resource Type | Number to Deploy | Total After Deployment | Limit/Capacity | Notes |
|---------------|------------------|------------------------|----------------|-------|
| Microsoft.Web/serverfarms Basic B1 | 1 | 2 | 11 plans | `az quota`: usage 1, available 10 |
| Microsoft.Web/sites | 1 | 3 | Provider validation passed | Current Central US usage 2; provider-level Bicep what-if passed |
| Microsoft.DBforPostgreSQL/flexibleServers Standard_B1ms | 1 | 3 | Regional capability available | Current Central US usage 2; quota API exposes no PostgreSQL quota rows; capability API confirms B1ms, zone 1, and 32 GiB |
| Microsoft.Storage/storageAccounts | 1 | 3 | 250 accounts | `az quota`: usage 2, available 248 |
| Microsoft.KeyVault/vaults | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.OperationalInsights/workspaces | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.Insights/components | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.Insights/webtests | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.Insights/metricAlerts | 2 | 2 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.Insights/actionGroups | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.ManagedIdentity/userAssignedIdentities | 1 | 1 | Provider validation passed | Provider registered and what-if passed |
| Microsoft.Authorization/roleAssignments | 2 | Existing usage + 2 | Inherited Owner access confirmed | Contributor and Cost Management Reader |
| Microsoft.Consumption/budgets | 1 | 1 | Budget API readable | Existing production budget absent |

**Status:** ✅ All resources are within limits. App Service B1 and Storage quotas have ample capacity; PostgreSQL uses the supported capability API fallback because Microsoft.Quota returns no rows for that provider.

## 7. Execution Checklist

### Phase 1: Planning
- [x] Analyze workspace
- [x] Gather requirements
- [x] Confirm subscription and location with user
- [x] Prepare resource inventory
- [x] Fetch quotas and validate capacity
- [x] Scan codebase
- [x] Select recipe
- [x] Plan architecture
- [x] User approved this plan and the billable/permission-changing production bootstrap

### Phase 2: Execution
- [x] Research components
- [x] Generate infrastructure and application configuration
- [x] Apply security hardening and OIDC design
- [x] Verify application locally
- [x] Update status to Ready for Validation

### Phase 3: Validation
- [x] Invoke azure-validate skill
- [x] All validation checks pass
- [x] Core validation: Azure CLI authentication, Bicep build, provider validation, and subscription what-if
- [x] Repository validation: lint, typecheck, tests, and production build
- [x] Infrastructure policy: credential-pattern scan and workflow lint
- [x] Azure policy assignments inspected for deployment blockers
- [x] Live role and quota readiness confirmed
- [x] Status set to Validated by azure-validate

### Phase 4: Deployment
- [x] Invoke azure-deploy skill
- [x] Bootstrap deployment successful
- [x] Live Azure resources, private endpoints, DNS, and RBAC verified
- [x] First exact-SHA application release successful
- [x] Report the deployed HTTPS endpoint
- [x] Update status to Deployed

## 7. Validation Proof

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|
| Production preflight | `scripts/azure/preflight-production.ps1 -SubscriptionId ad92e163-a85e-40cc-bb50-054b0b8197a8 -Location centralus` | ✅ Ready: 13/13 checks; provider what-if reported 19 changes | 2026-10-04T13:28:57Z |
| Bicep and credential policy | `bash scripts/azure/validate-bicep.sh` | ✅ Pass | 2026-10-04T13:24:00Z |
| Workflow lint | `actionlint .github/workflows/release-health.yml` | ✅ Pass | 2026-10-04T13:24:00Z |
| Application lint | `npm run lint` | ✅ Pass | 2026-10-04T13:23:28Z |
| Type checking | `npm run typecheck` | ✅ Pass | 2026-10-04T13:23:28Z |
| Tests | `npm test` | ✅ 7 files, 25 tests passed | 2026-10-04T13:24:01Z |
| Production build | `npm run build` | ✅ Pass | 2026-10-04T13:24:28Z |
| Dependency audit | `npm audit --omit=dev` | ✅ 0 vulnerabilities | 2026-10-04T13:24:00Z |
| App Service quota | Azure quota script for `Microsoft.Web`, Central US | ✅ B1 limit 11, usage 1, available 10 | 2026-10-04T13:19:00Z |
| Storage quota | Azure quota script for `Microsoft.Storage`, Central US | ✅ Limit 250, usage 2, available 248 | 2026-10-04T13:19:00Z |
| PostgreSQL capability | `az postgres flexible-server list-skus --location centralus` | ✅ B1ms, zone 1, 32 GiB supported | 2026-10-04T13:19:00Z |
| Azure policies | Azure Policy assignment inspection and deny-definition review | ✅ No deny applies to planned ARM resource types; provider what-if passed | 2026-10-04T13:28:00Z |
| Static roles | Review of `bootstrap-production.ps1` identity, role, and scope mappings | ✅ Least-privilege data-plane role present; management roles match controller operations | 2026-10-04T13:29:00Z |
| Private infrastructure deployment | `scripts/azure/bootstrap-production.ps1 -SubscriptionId ad92e163-a85e-40cc-bb50-054b0b8197a8 -Location centralus` | ✅ VNet integration and PostgreSQL, Key Vault, and Blob private endpoints deployed | 2026-10-04T14:54:00Z |
| Private endpoint verification | `az network private-endpoint list -g rg-meme-forge-production` | ✅ Three connections approved | 2026-10-04T14:57:00Z |
| Private DNS verification | `az network private-dns record-set a list ...` | ✅ PostgreSQL, Key Vault, and Blob names resolve to `10.20.2.x` | 2026-10-04T14:59:00Z |
| Application package smoke test | `RELEASE_SHA=$(git rev-parse HEAD) scripts/release/package-app.sh` | ✅ Standalone server, Prisma CLI, migrations, and executable startup script packaged | 2026-10-04T14:49:00Z |
| Updated tests | `npm test -- --maxWorkers=2` | ✅ 8 files, 33 tests passed, including GitHub OIDC issuer/audience/repository/subject/signature validation | 2026-10-04T17:35:00Z |
| Repository OIDC customization | `gh api repos/The-weyland-yutani-corporation/meme-sticker-e-commerce-store/actions/oidc/customization/sub` | ✅ GitHub reports `use_immutable_subject: true` and `sub_claim_prefix: repo:The-weyland-yutani-corporation@264313301/meme-sticker-e-commerce-store@1385623955` | 2026-10-04T18:51:00Z |
| Immutable OIDC specification | [GitHub changelog](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/), [GitHub repository OIDC API](https://docs.github.com/en/rest/actions/oidc#get-the-customization-template-for-an-oidc-subject-claim-for-a-repository), and [Microsoft Entra migration guidance](https://learn.microsoft.com/en-us/entra/workload-id/workload-identities-github-immutable-subjects) | ✅ Official sources document the `repo:owner@owner_id/repository@repository_id` format plus the `use_immutable_subject` and `sub_claim_prefix` response fields | 2026-10-04T20:03:00Z |
| Live GitHub OIDC assertion | `gh run view 37223574750 --log-failed` | ✅ Azure Login logged the presented subject as `repo:The-weyland-yutani-corporation@264313301/meme-sticker-e-commerce-store@1385623955:environment:production`; the run failed because Azure still trusted the legacy subject | 2026-10-04T18:51:00Z |
| Stable GitHub federation | `az identity federated-credential show ...` | ✅ Subject reconciled to `owner@id/repository@id:environment:production`, matching the live GitHub claim | 2026-10-04T18:24:00Z |
| Autonomous production release | [GitHub Actions run `37263203006`](https://github.com/The-weyland-yutani-corporation/meme-sticker-e-commerce-store/actions/runs/37263203006) | ✅ Exact SHA `767a27002e94ce071fbfe93674845d0e7ba0041c` deployed from retained artifact `production-package-767a27002e94ce071fbfe93674845d0e7ba0041c`; GitHub deployment `6851340806` and Azure OneDeploy `57fd724c-6be7-48a8-9f26-4f81cdc85578` succeeded | 2026-10-05T04:31:42Z |
| Production application gates | `scripts/release/probe-release.sh https://memeforge-app-hkxi7iyrxtbso.azurewebsites.net` in run `37263203006` | ✅ Exact-SHA health, storefront HTML, database access, GitHub OIDC authentication, synthetic-order creation, and verified deletion passed | 2026-10-05T04:31:42Z |
| Monitor-only reconciliation | [GitHub Actions run `37263952310`](https://github.com/The-weyland-yutani-corporation/meme-sticker-e-commerce-store/actions/runs/37263952310) | ✅ Controller selected the no-deploy path and repeated all production probes successfully | 2026-10-05T04:32:26Z |
| Retained-package rollback | [GitHub Actions run `37260482653`](https://github.com/The-weyland-yutani-corporation/meme-sticker-e-commerce-store/actions/runs/37260482653) | ✅ A failed forward upload restored retained SHA `c9be05a1fafd7236870cf0020a626a7619f82ad3`, then passed exact-SHA, storefront, database, and synthetic-order cleanup gates without database rollback | 2026-10-05T03:51:22Z |

**Validated by:** azure-validate skill workflow

**Deployed by:** autonomous Azure release controller

## 8. Files

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | Deployment source of truth | Deployed and verified |
| `infra/main.bicep` | Production resource graph | Deployed |
| `infra/main.bicepparam` | Central US production parameters | Ready |
| `infra/preflight.bicep` | Read-only subscription provider validation | Ready |
| `scripts/azure/bootstrap-production.ps1` | Approved one-time owner bootstrap | Ready |
| `scripts/azure/preflight-production.ps1` | Non-mutating readiness validation | Ready |

## 9. Operating State

> Current: lights-off production reconciliation

1. The 15-minute release controller reconciles the latest `main` SHA to production.
2. Exact-SHA health, storefront, database, and authenticated synthetic-order cleanup determine release and monitoring success.
3. Failed application releases restore the previous retained package; database migrations remain additive-only and are never rolled back.
4. Production endpoint: https://memeforge-app-hkxi7iyrxtbso.azurewebsites.net
