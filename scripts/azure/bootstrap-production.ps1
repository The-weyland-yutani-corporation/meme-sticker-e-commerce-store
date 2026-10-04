param(
  [string]$SubscriptionId = $env:AZURE_SUBSCRIPTION_ID,
  [string]$Location = "centralus",
  [string]$ResourceGroup = "rg-meme-forge-production",
  [string]$IdentityName = "id-meme-forge-github",
  [string]$Repository = "The-weyland-yutani-corporation/meme-sticker-e-commerce-store",
  [string]$NamePrefix = "memeforge",
  [int]$MonthlyBudgetUsd = 75
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (-not $SubscriptionId) {
  throw "Pass -SubscriptionId or set AZURE_SUBSCRIPTION_ID."
}

function New-RandomHex([int]$ByteCount) {
  $bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes($ByteCount)
  return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

az account set --subscription $SubscriptionId
az group create --name $ResourceGroup --location $Location --output none

$identity = az identity create `
  --resource-group $ResourceGroup `
  --name $IdentityName `
  --location $Location | ConvertFrom-Json

$subject = "repo:${Repository}:environment:production"
$credentialName = "github-production"
$existingCredential = az identity federated-credential list `
  --resource-group $ResourceGroup `
  --identity-name $IdentityName `
  --query "[?name=='$credentialName'] | [0]" | ConvertFrom-Json

if (-not $existingCredential) {
  az identity federated-credential create `
    --resource-group $ResourceGroup `
    --identity-name $IdentityName `
    --name $credentialName `
    --issuer "https://token.actions.githubusercontent.com" `
    --subject $subject `
    --audiences "api://AzureADTokenExchange" `
    --output none
}

$resourceGroupId = az group show --name $ResourceGroup --query id --output tsv
$subscriptionScope = "/subscriptions/$SubscriptionId"
$contributorRole = az role assignment list `
  --assignee-object-id $identity.principalId `
  --scope $resourceGroupId `
  --role "Contributor" `
  --query "[0].id" --output tsv
if (-not $contributorRole) {
  az role assignment create `
    --assignee-object-id $identity.principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $resourceGroupId `
    --role "Contributor" `
    --output none
}

$costReaderRole = az role assignment list `
  --assignee-object-id $identity.principalId `
  --scope $subscriptionScope `
  --role "Cost Management Reader" `
  --query "[0].id" --output tsv
if (-not $costReaderRole) {
  az role assignment create `
    --assignee-object-id $identity.principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $subscriptionScope `
    --role "Cost Management Reader" `
    --output none
}

$postgresPassword = $null
$probeToken = $null
$existingAppName = az webapp list `
  --resource-group $ResourceGroup `
  --query "[?starts_with(name, '$NamePrefix-app-')].name | [0]" `
  --output tsv

if ($existingAppName) {
  $existingSettings = az webapp config appsettings list `
    --resource-group $ResourceGroup `
    --name $existingAppName | ConvertFrom-Json
  $existingDatabaseUrl = $existingSettings |
    Where-Object { $_.name -eq "DATABASE_URL" } |
    Select-Object -ExpandProperty value -First 1
  $existingProbeToken = $existingSettings |
    Where-Object { $_.name -eq "SYNTHETIC_PROBE_TOKEN" } |
    Select-Object -ExpandProperty value -First 1

  if ($existingDatabaseUrl -and $existingDatabaseUrl.StartsWith("postgresql://")) {
    $databaseUri = [Uri]$existingDatabaseUrl
    $databaseUserInfo = $databaseUri.UserInfo.Split(":", 2)
    if ($databaseUserInfo.Count -eq 2) {
      $postgresPassword = [Uri]::UnescapeDataString($databaseUserInfo[1])
    }
  }
  if ($existingProbeToken -and -not $existingProbeToken.StartsWith("@Microsoft.KeyVault(")) {
    $probeToken = $existingProbeToken
  }
}

if (-not $postgresPassword) {
  $postgresPassword = "Aa1-$(New-RandomHex 30)"
}
if (-not $probeToken) {
  $probeToken = New-RandomHex 32
}

az deployment group what-if `
  --resource-group $ResourceGroup `
  --template-file "infra/main.bicep" `
  --parameters `
    location=$Location `
    namePrefix=$NamePrefix `
    deploymentPrincipalObjectId=$($identity.principalId) `
    postgresAdminPassword=$postgresPassword `
    syntheticProbeToken=$probeToken `
    releaseSha=bootstrap `
  --no-pretty-print | Out-Null

az deployment group create `
  --resource-group $ResourceGroup `
  --template-file "infra/main.bicep" `
  --parameters `
    location=$Location `
    namePrefix=$NamePrefix `
    deploymentPrincipalObjectId=$($identity.principalId) `
    postgresAdminPassword=$postgresPassword `
    syntheticProbeToken=$probeToken `
    releaseSha=bootstrap `
  --output none

$subscription = az account show | ConvertFrom-Json
$outputs = az deployment group show `
  --resource-group $ResourceGroup `
  --name main `
  --query properties.outputs | ConvertFrom-Json

$storageId = az storage account show `
  --resource-group $ResourceGroup `
  --name $outputs.storageAccountName.value `
  --query id --output tsv
$blobContributorRole = az role assignment list `
  --assignee-object-id $identity.principalId `
  --scope $storageId `
  --role "Storage Blob Data Contributor" `
  --query "[0].id" --output tsv
if (-not $blobContributorRole) {
  az role assignment create `
    --assignee-object-id $identity.principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $storageId `
    --role "Storage Blob Data Contributor" `
    --output none
}

$env:AZURE_APP_NAME = $outputs.appName.value
$env:AZURE_POSTGRES_NAME = $outputs.postgresName.value
$env:AZURE_RESOURCE_GROUP = $ResourceGroup
bash scripts/azure/configure-postgres-firewall.sh

'{}' | gh api --method PUT `
  "repos/$Repository/environments/production" `
  --input - | Out-Null

$variables = @{
  AZURE_CLIENT_ID       = $identity.clientId
  AZURE_PRINCIPAL_OBJECT_ID = $identity.principalId
  AZURE_TENANT_ID       = $subscription.tenantId
  AZURE_SUBSCRIPTION_ID = $subscription.id
  AZURE_RESOURCE_GROUP  = $ResourceGroup
  AZURE_LOCATION        = $Location
  AZURE_NAME_PREFIX     = $NamePrefix
  APP_URL               = $outputs.appUrl.value
  AZURE_APP_NAME        = $outputs.appName.value
  AZURE_KEY_VAULT_NAME  = $outputs.keyVaultName.value
  AZURE_POSTGRES_NAME   = $outputs.postgresName.value
  AZURE_STORAGE_ACCOUNT = $outputs.storageAccountName.value
  AZURE_RELEASE_CONTAINER = $outputs.releaseContainerName.value
  AZURE_MONTHLY_BUDGET_USD = "$MonthlyBudgetUsd"
}

foreach ($entry in $variables.GetEnumerator()) {
  gh variable set $entry.Key `
    --repo $Repository `
    --env production `
    --body ([string]$entry.Value)
}

$budgetStart = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0 -Format "yyyy-MM-dd"
$budgetEnd = (Get-Date $budgetStart).AddYears(10).ToString("yyyy-MM-dd")
$budgetFile = New-TemporaryFile
try {
  @{
    properties = @{
      amount = $MonthlyBudgetUsd
      category = "Cost"
      timeGrain = "Monthly"
      timePeriod = @{
        startDate = "${budgetStart}T00:00:00Z"
        endDate = "${budgetEnd}T00:00:00Z"
      }
    }
  } |
    ConvertTo-Json -Depth 5 |
    Set-Content -Path $budgetFile -Encoding utf8

  az rest `
    --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Consumption/budgets/meme-forge-production?api-version=2023-11-01" `
    --body "@$budgetFile" `
    --output none
}
finally {
  Remove-Item $budgetFile -Force -ErrorAction SilentlyContinue
}

Write-Output "Azure production bootstrap complete."
Write-Output "App URL: $($outputs.appUrl.value)"
Write-Output "OIDC client ID: $($identity.clientId)"
