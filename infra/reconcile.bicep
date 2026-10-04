targetScope = 'resourceGroup'

@description('Azure region for production resources.')
param location string = resourceGroup().location

@description('Stable lowercase prefix used for globally unique resource names.')
@minLength(3)
@maxLength(12)
param namePrefix string

@description('Object ID of the GitHub OIDC deployment identity.')
param deploymentPrincipalObjectId string

@description('Git SHA deployed by the release controller.')
param releaseSha string

var suffix = uniqueString(subscription().subscriptionId, resourceGroup().id)
var keyVaultName = take('${namePrefix}-kv-${suffix}', 24)

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

module production 'main.bicep' = {
  name: 'production'
  params: {
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    location: location
    namePrefix: namePrefix
    postgresAdminPassword: keyVault.getSecret('postgres-admin-password')
    releaseSha: releaseSha
    syntheticProbeToken: keyVault.getSecret('synthetic-probe-token')
  }
}

output appName string = production.outputs.appName
output appUrl string = production.outputs.appUrl
output appInsightsName string = production.outputs.appInsightsName
output keyVaultName string = production.outputs.keyVaultName
output postgresName string = production.outputs.postgresName
output releaseContainerName string = production.outputs.releaseContainerName
output storageAccountName string = production.outputs.storageAccountName
