// =============================================================================
// Extra Storage Module
// =============================================================================
// Deploys a standalone storage account and blob container used for multi-stack
// throttling and dependency demonstrations.
// =============================================================================

@description('Name of the storage account')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

var containerName = 'demo-throttle'

// =============================================================================
// RESOURCES
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource throttleContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployMultiStack)`:
//   module storageExtra 'modules/storage-extra.bicep' = if (deployMultiStack) {
//     scope: resourceGroup
//     name: 'deploy-storage-extra'
//     params: {
//       name: names.storageExtra
//       location: location
//       tags: tags
//     }
//   }
