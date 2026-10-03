targetScope = 'subscription'

@description('Azure region for production resources.')
param location string = 'centralus'

@description('Production resource group name.')
param resourceGroupName string = 'rg-meme-forge-production'

@description('Stable lowercase prefix used for globally unique resource names.')
@minLength(3)
@maxLength(12)
param namePrefix string = 'memeforge'

@description('Object ID used only for provider validation of Key Vault access policies.')
param deploymentPrincipalObjectId string

@secure()
@description('Non-production placeholder used only during the read-only what-if.')
param postgresAdminPassword string

@secure()
@description('Non-production placeholder used only during the read-only what-if.')
param syntheticProbeToken string

resource productionResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module production './main.bicep' = {
  name: 'meme-forge-production-preflight'
  scope: productionResourceGroup
  params: {
    deploymentPrincipalObjectId: deploymentPrincipalObjectId
    location: location
    namePrefix: namePrefix
    postgresAdminPassword: postgresAdminPassword
    releaseSha: 'preflight'
    syntheticProbeToken: syntheticProbeToken
  }
}

output appName string = production.outputs.appName
output appUrl string = production.outputs.appUrl
output keyVaultName string = production.outputs.keyVaultName
output postgresName string = production.outputs.postgresName
output resourceGroup string = productionResourceGroup.name
output storageAccountName string = production.outputs.storageAccountName
