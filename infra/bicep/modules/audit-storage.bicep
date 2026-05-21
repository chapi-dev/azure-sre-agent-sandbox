// =============================================================================
// Audit Storage Module
// =============================================================================
// Deploys immutable blob storage for SRE Agent tool-call audits and grants the
// agent managed identity write access at the container scope.
// =============================================================================

@description('Name of the storage account (must be globally unique and lowercase).')
param name string

@description('Azure region for deployment.')
param location string

@description('Tags to apply to resources.')
param tags object

@description('Principal ID of the SRE Agent managed identity that will write audit blobs.')
param sreAgentPrincipalId string

var storageAccountName = toLower(name)
var containerName = 'agent-audit'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
  }
}

resource immutabilityPolicy 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-05-01' = {
  parent: auditContainer
  name: 'default'
  properties: {
    allowProtectedAppendWritesAll: false
    immutabilityPeriodSinceCreationInDays: 90
  }
}

resource auditBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(auditContainer.id, sreAgentPrincipalId, storageBlobDataContributorRoleId)
  scope: auditContainer
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: sreAgentPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob

// =============================================================================
// Integration note
// =============================================================================
// Expected main.bicep usage:
// module auditStorage 'modules/audit-storage.bicep' = if (deployHooks) {
//   name: 'audit-storage'
//   params: {
//     name: 'staudit${uniqueSuffix}'
//     location: location
//     tags: tags
//     sreAgentPrincipalId: sreAgent.outputs.managedIdentityPrincipalId
//   }
// }