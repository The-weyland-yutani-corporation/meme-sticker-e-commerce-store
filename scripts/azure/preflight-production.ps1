param(
  [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
  [string]$TenantId = "1cf61a60-a877-46a7-86bc-a8f76b6ab441",
  [string]$Location = "centralus",
  [string]$ResourceGroup = "rg-meme-forge-production",
  [string]$IdentityName = "id-meme-forge-github",
  [string]$Repository = "The-weyland-yutani-corporation/meme-sticker-e-commerce-store",
  [string]$NamePrefix = "memeforge",
  [int]$MonthlyBudgetUsd = 75,
  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if (-not $SubscriptionId) {
  throw "Pass -SubscriptionId or set AZURE_SUBSCRIPTION_ID."
}

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check(
  [string]$Name,
  [ValidateSet("ready", "blocked", "already_configured")]
  [string]$State,
  [string]$Evidence
) {
  $checks.Add([ordered]@{
      name = $Name
      state = $State
      evidence = $Evidence
    })
}

function Invoke-JsonCommand([string]$Command, [string[]]$Arguments) {
  $output = & $Command @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "$Command failed: $(($output | Out-String).Trim())"
  }

  $text = ($output | Out-String).Trim()
  if (-not $text) {
    return $null
  }

  return $text | ConvertFrom-Json
}

function Invoke-Check([string]$Name, [scriptblock]$Check) {
  try {
    & $Check
  }
  catch {
    Add-Check $Name "blocked" $_.Exception.Message
  }
}

Invoke-Check "tooling" {
  $az = Get-Command az -ErrorAction Stop
  $gh = Get-Command gh -ErrorAction Stop
  Add-Check "tooling" "ready" "Azure CLI: $($az.Source); GitHub CLI: $($gh.Source)"
}

$script:account = $null
Invoke-Check "azure-account" {
  $script:account = Invoke-JsonCommand "az" @(
    "account", "show",
    "--only-show-errors",
    "--output", "json"
  )
  if ($script:account.id -ne $SubscriptionId) {
    throw "Active subscription '$($script:account.id)' does not match '$SubscriptionId'."
  }
  if ($script:account.tenantId -ne $TenantId) {
    throw "Active tenant '$($script:account.tenantId)' does not match '$TenantId'."
  }
  Add-Check "azure-account" "ready" "Subscription and tenant match the production target."
}

$script:principalObjectId = $null
Invoke-Check "azure-principal" {
  $tokenResult = Invoke-JsonCommand "az" @(
    "account", "get-access-token",
    "--resource", "https://management.azure.com/",
    "--only-show-errors",
    "--output", "json"
  )
  $tokenParts = $tokenResult.accessToken.Split(".")
  if ($tokenParts.Count -lt 2) {
    throw "Azure access token did not contain a JWT payload."
  }
  $payload = $tokenParts[1].Replace("-", "+").Replace("_", "/")
  switch ($payload.Length % 4) {
    2 { $payload += "==" }
    3 { $payload += "=" }
  }
  $claims = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($payload)
  ) | ConvertFrom-Json
  $script:principalObjectId = $claims.oid
  if (-not $script:principalObjectId) {
    throw "Azure access token did not include the signed-in principal object ID."
  }
  Add-Check "azure-principal" "ready" "Signed-in principal object ID resolved."
}

Invoke-Check "azure-permissions" {
  $assignments = @(Invoke-JsonCommand "az" @(
      "role", "assignment", "list",
      "--include-inherited",
      "--all",
      "--fill-principal-name", "false",
      "--only-show-errors",
      "--output", "json"
    ))
  $sufficient = @($assignments | Where-Object {
      $_.roleDefinitionName -eq "Owner" -and (
        $_.scope -eq "/subscriptions/$SubscriptionId" -or
        $_.scope -like "/providers/Microsoft.Management/managementGroups/*"
      )
    })
  if ($sufficient.Count -eq 0) {
    throw "No inherited Owner assignment covers the target subscription."
  }
  Add-Check "azure-permissions" "ready" "Inherited Owner access covers resource and role-assignment creation."
}

Invoke-Check "azure-providers" {
  $requiredProviders = @(
    "Microsoft.Authorization",
    "Microsoft.Consumption",
    "Microsoft.DBforPostgreSQL",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage",
    "Microsoft.Web"
  )
  $missing = [System.Collections.Generic.List[string]]::new()
  foreach ($provider in $requiredProviders) {
    $state = (& az provider show --namespace $provider --query registrationState --output tsv --only-show-errors 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $state -ne "Registered") {
      $missing.Add("$provider=$state")
    }
  }
  if ($missing.Count -gt 0) {
    throw "Required providers are not registered: $($missing -join ', ')."
  }
  Add-Check "azure-providers" "ready" "All required resource providers are registered."
}

Invoke-Check "app-service-capability" {
  $locations = @(Invoke-JsonCommand "az" @(
      "appservice", "list-locations",
      "--sku", "B1",
      "--linux-workers-enabled",
      "--only-show-errors",
      "--output", "json"
    ))
  $normalizedLocation = $Location.Replace(" ", "")
  $match = @($locations | Where-Object {
      $_.name.Replace(" ", "").Equals($normalizedLocation, [System.StringComparison]::OrdinalIgnoreCase)
    })
  if ($match.Count -eq 0) {
    throw "Linux App Service B1 is unavailable in '$Location'."
  }
  Add-Check "app-service-capability" "ready" "Linux App Service B1 is available in $Location."
}

Invoke-Check "postgres-capability" {
  $capabilities = Invoke-JsonCommand "az" @(
    "postgres", "flexible-server", "list-skus",
    "--location", $Location,
    "--only-show-errors",
    "--output", "json"
  )
  $burstable = $capabilities.supportedServerEditions |
    Where-Object { $_.name -eq "Burstable" } |
    Select-Object -First 1
  $sku = $burstable.supportedServerSkus |
    Where-Object { $_.name -eq "Standard_B1ms" } |
    Select-Object -First 1
  $storage32GiB = @(
    $burstable.supportedStorageEditions.supportedStorageMb |
      Where-Object { $_.storageSizeMb -eq 32768 }
  )
  if (-not $sku) {
    throw "PostgreSQL Standard_B1ms is unavailable in '$Location'."
  }
  if (@($sku.supportedZones) -notcontains "1") {
    throw "PostgreSQL Standard_B1ms does not support availability zone 1 in '$Location'."
  }
  if ($storage32GiB.Count -eq 0) {
    throw "PostgreSQL 32 GiB storage is unavailable in '$Location'."
  }
  Add-Check "postgres-capability" "ready" "Standard_B1ms, zone 1, and 32 GiB storage are available in $Location."
}

$script:resourceGroupExists = $false
$script:deploymentExists = $false
Invoke-Check "resource-state" {
  $resourceGroupExistsText = (& az group exists --name $ResourceGroup --subscription $SubscriptionId 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Could not query resource group '$ResourceGroup'."
  }
  $script:resourceGroupExists = $resourceGroupExistsText -eq "true"
  if (-not $script:resourceGroupExists) {
    Add-Check "resource-state" "ready" "Resource group '$ResourceGroup' is available for bootstrap."
    return
  }

  $deployments = @(Invoke-JsonCommand "az" @(
      "deployment", "group", "list",
      "--resource-group", $ResourceGroup,
      "--subscription", $SubscriptionId,
      "--only-show-errors",
      "--output", "json"
    ))
  $script:deploymentExists = @($deployments | Where-Object { $_.name -eq "main" }).Count -gt 0
  if (-not $script:deploymentExists) {
    throw "Resource group '$ResourceGroup' exists without the expected 'main' deployment."
  }
  Add-Check "resource-state" "already_configured" "Resource group and main production deployment already exist."
}

Invoke-Check "federated-credential-state" {
  if (-not $script:resourceGroupExists) {
    Add-Check "federated-credential-state" "ready" "No existing resource group or conflicting production identity was found."
    return
  }

  $identities = @(Invoke-JsonCommand "az" @(
      "identity", "list",
      "--resource-group", $ResourceGroup,
      "--subscription", $SubscriptionId,
      "--only-show-errors",
      "--output", "json"
    ))
  $identity = $identities | Where-Object { $_.name -eq $IdentityName } | Select-Object -First 1
  if (-not $identity) {
    throw "Resource group exists but identity '$IdentityName' is missing."
  }
  $credentials = @(Invoke-JsonCommand "az" @(
      "identity", "federated-credential", "list",
      "--resource-group", $ResourceGroup,
      "--identity-name", $IdentityName,
      "--only-show-errors",
      "--output", "json"
    ))
  $credential = $credentials | Where-Object { $_.name -eq "github-production" } | Select-Object -First 1
  $expectedSubject = "repo:${Repository}:environment:production"
  if (
    -not $credential -or
    $credential.issuer -ne "https://token.actions.githubusercontent.com" -or
    $credential.subject -ne $expectedSubject -or
    @($credential.audiences) -notcontains "api://AzureADTokenExchange"
  ) {
    throw "Existing GitHub production federated credential is missing or does not match the expected trust subject."
  }
  Add-Check "federated-credential-state" "already_configured" "Existing OIDC federation matches the production environment subject."
}

Invoke-Check "github-environment-access" {
  $repositoryState = Invoke-JsonCommand "gh" @(
    "api", "repos/$Repository"
  )
  if (-not $repositoryState.permissions.admin) {
    throw "The active GitHub identity does not have repository administration permission."
  }
  $environments = Invoke-JsonCommand "gh" @(
    "api", "repos/$Repository/environments?per_page=100"
  )
  $productionEnvironment = @($environments.environments | Where-Object { $_.name -eq "production" })
  if ($productionEnvironment.Count -eq 0) {
    Add-Check "github-environment-access" "ready" "Repository administration is available and the production environment is available for bootstrap."
    return
  }

  $variableState = Invoke-JsonCommand "gh" @(
    "api", "repos/$Repository/environments/production/variables?per_page=100"
  )
  $expectedVariables = @(
    "APP_URL",
    "AZURE_APP_NAME",
    "AZURE_CLIENT_ID",
    "AZURE_KEY_VAULT_NAME",
    "AZURE_LOCATION",
    "AZURE_MONTHLY_BUDGET_USD",
    "AZURE_NAME_PREFIX",
    "AZURE_POSTGRES_NAME",
    "AZURE_PRINCIPAL_OBJECT_ID",
    "AZURE_RELEASE_CONTAINER",
    "AZURE_RESOURCE_GROUP",
    "AZURE_STORAGE_ACCOUNT",
    "AZURE_SUBSCRIPTION_ID",
    "AZURE_TENANT_ID"
  )
  $existingVariables = @(
    $variableState.variables |
      ForEach-Object { $_.name } |
      Where-Object { $_ }
  )
  $unexpectedVariables = @($existingVariables | Where-Object { $_ -notin $expectedVariables })
  $missingVariables = @($expectedVariables | Where-Object { $_ -notin $existingVariables })
  if ($existingVariables.Count -gt 0 -and ($unexpectedVariables.Count -gt 0 -or $missingVariables.Count -gt 0)) {
    throw "Production environment variables are partially or unexpectedly configured. Missing: $($missingVariables -join ', '); unexpected: $($unexpectedVariables -join ', ')."
  }
  $state = if ($existingVariables.Count -eq $expectedVariables.Count) { "already_configured" } else { "ready" }
  Add-Check "github-environment-access" $state "Repository administration is available; production environment has $($existingVariables.Count) configured variables."
}

Invoke-Check "budget-access" {
  $budgets = @(Invoke-JsonCommand "az" @(
    "consumption", "budget", "list",
    "--subscription", $SubscriptionId,
    "--only-show-errors",
    "--output", "json"
  ))
  $budget = $budgets | Where-Object { $_.name -eq "meme-forge-production" } | Select-Object -First 1
  if (-not $budget) {
    Add-Check "budget-access" "ready" "Subscription budget state is readable and the production budget is available for bootstrap."
    return
  }
  if ([decimal]$budget.amount -ne [decimal]$MonthlyBudgetUsd) {
    throw "Existing production budget amount '$($budget.amount)' does not match '$MonthlyBudgetUsd'."
  }
  Add-Check "budget-access" "already_configured" "The existing production budget matches the expected monthly amount."
}

Invoke-Check "bicep-build" {
  $buildOutput = & az bicep build --file infra/main.bicep --stdout 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "main.bicep compilation failed: $(($buildOutput | Out-String).Trim())"
  }
  $preflightBuildOutput = & az bicep build --file infra/preflight.bicep --stdout 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "preflight.bicep compilation failed: $(($preflightBuildOutput | Out-String).Trim())"
  }
  Add-Check "bicep-build" "ready" "Production and subscription preflight Bicep templates compile."
}

Invoke-Check "provider-what-if" {
  if (-not $script:principalObjectId) {
    throw "Azure principal object ID is unavailable for provider validation."
  }
  $whatIf = Invoke-JsonCommand "az" @(
    "deployment", "sub", "what-if",
    "--name", "meme-forge-production-preflight",
    "--location", $Location,
    "--subscription", $SubscriptionId,
    "--template-file", "infra/preflight.bicep",
    "--parameters",
    "location=$Location",
    "resourceGroupName=$ResourceGroup",
    "namePrefix=$NamePrefix",
    "deploymentPrincipalObjectId=$script:principalObjectId",
    "postgresAdminPassword=Preflight-Only-Aa1-000000000000000000000000",
    "syntheticProbeToken=preflight-only-not-a-production-secret",
    "--result-format", "ResourceIdOnly",
    "--validation-level", "Provider",
    "--no-pretty-print",
    "--no-prompt",
    "--only-show-errors",
    "--output", "json"
  )
  $changes = @($whatIf.changes)
  if ($changes.Count -eq 0 -and $whatIf.properties) {
    $changes = @($whatIf.properties.changes)
  }
  Add-Check "provider-what-if" "ready" "Provider validation and exact-name what-if completed with $($changes.Count) reported resource changes."
}

$blocked = @($checks | Where-Object { $_.state -eq "blocked" })
$overallState = if ($blocked.Count -gt 0) {
  "blocked"
}
elseif ($script:resourceGroupExists -and $script:deploymentExists) {
  "already_configured"
}
else {
  "ready"
}

$report = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  state = $overallState
  target = [ordered]@{
    subscription_id = $SubscriptionId
    tenant_id = $TenantId
    location = $Location
    resource_group = $ResourceGroup
    identity_name = $IdentityName
    repository = $Repository
    name_prefix = $NamePrefix
    monthly_budget_usd = $MonthlyBudgetUsd
  }
  checks = $checks
}

$json = $report | ConvertTo-Json -Depth 10
if ($OutputPath) {
  $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
  $parent = Split-Path -Parent $resolvedOutputPath
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  Set-Content -Path $resolvedOutputPath -Value $json -Encoding utf8
}

Write-Output $json
if ($blocked.Count -gt 0) {
  exit 1
}
