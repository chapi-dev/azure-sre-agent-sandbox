// =============================================================================
// Citrix MCP Key Vault Secrets Module
// =============================================================================
// Writes demo Citrix Cloud credentials and the MCP bearer token into an
// existing Azure Key Vault so the container app can reference them securely.
// =============================================================================

@description('Name of the existing Azure Key Vault')
param keyVaultName string

@description('Citrix Cloud customer ID')
param citrixCustomerId string

@description('Citrix Cloud client ID')
param citrixClientId string

@secure()
@description('Citrix Cloud client secret')
param citrixClientSecret string

@secure()
@description('Shared bearer token used to protect inbound MCP requests')
param mcpBearerToken string

var secretNames = {
  customerId: 'citrix-customer-id'
  clientId: 'citrix-client-id'
  clientSecret: 'citrix-client-secret'
  mcpBearerToken: 'citrix-mcp-bearer-token'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

var keyVaultUri = keyVault.properties.vaultUri

resource citrixCustomerIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: secretNames.customerId
  parent: keyVault
  properties: {
    value: citrixCustomerId
  }
}

resource citrixClientIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: secretNames.clientId
  parent: keyVault
  properties: {
    value: citrixClientId
  }
}

resource citrixClientSecretSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: secretNames.clientSecret
  parent: keyVault
  properties: {
    value: citrixClientSecret
  }
}

resource mcpBearerTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: secretNames.mcpBearerToken
  parent: keyVault
  properties: {
    value: mcpBearerToken
  }
}

output secretIds object = {
  customerId: '${keyVaultUri}secrets/${secretNames.customerId}'
  clientId: '${keyVaultUri}secrets/${secretNames.clientId}'
  clientSecret: '${keyVaultUri}secrets/${secretNames.clientSecret}'
  mcpBearerToken: '${keyVaultUri}secrets/${secretNames.mcpBearerToken}'
}

// Wire-up notes:
// - Call this helper before citrix-mcp-container.bicep if you want Container Apps secrets backed by Key Vault.
// - The default secret names match the defaults expected by citrix-mcp-container.bicep.
// - Main deployment script integration is intentionally left for the final integration pass.
