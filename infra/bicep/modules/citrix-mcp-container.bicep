// =============================================================================
// Citrix MCP Container App Module
// =============================================================================
// Deploys a minimal Azure Container Apps environment and a single container app
// that exposes the custom Citrix MCP server over HTTPS.
// =============================================================================

@description('Name of the Citrix MCP container app')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Optional image override. Leave empty to default to <acrLoginServer>/citrix-mcp:latest.')
param image string = ''

@description('Resource ID of the Azure Container Registry that stores the citrix-mcp image')
param acrId string

@description('Optional Key Vault resource ID. Leave empty to use inline secure parameters instead of Key Vault-backed Container Apps secrets.')
param keyVaultId string = ''

@description('Secret names in Key Vault for the Citrix customer, client ID, and client secret')
#disable-next-line secure-secrets-in-params
param citrixSecretsNames object = {
  customerId: 'citrix-customer-id'
  clientId: 'citrix-client-id'
  clientSecret: 'citrix-client-secret'
}

@description('Secret name in Key Vault for the MCP bearer token')
param mcpBearerTokenSecretName string = 'citrix-mcp-bearer-token'

@secure()
@description('Inline fallback for the Citrix customer ID when Key Vault references are not used')
param citrixCustomerId string = ''

@secure()
@description('Inline fallback for the Citrix client ID when Key Vault references are not used')
param citrixClientId string = ''

@secure()
@description('Inline fallback for the Citrix client secret when Key Vault references are not used')
param citrixClientSecret string = ''

@secure()
@description('Inline fallback for the shared MCP bearer token when Key Vault references are not used')
param mcpBearerToken string = ''

var managedEnvironmentName = '${name}-env'
var acrName = last(split(acrId, '/'))
var useKeyVaultReferences = !empty(keyVaultId)
var keyVaultName = useKeyVaultReferences ? last(split(keyVaultId, '/')) : ''
var containerImage = empty(image) ? '${acr.properties.loginServer}/citrix-mcp:latest' : image
var secretAliases = {
  customerId: 'citrix-customer-id'
  clientId: 'citrix-client-id'
  clientSecret: 'citrix-client-secret'
  mcpBearerToken: 'citrix-mcp-bearer-token'
}
var keyVaultUri = useKeyVaultReferences ? keyVault!.properties.vaultUri : ''
var customerIdSecrets = useKeyVaultReferences
  ? [
      {
        name: secretAliases.customerId
        identity: 'system'
        keyVaultUrl: '${keyVaultUri}secrets/${citrixSecretsNames.customerId}'
      }
    ]
  : (!empty(citrixCustomerId)
      ? [
          {
            name: secretAliases.customerId
            value: citrixCustomerId
          }
        ]
      : [])
var clientIdSecrets = useKeyVaultReferences
  ? [
      {
        name: secretAliases.clientId
        identity: 'system'
        keyVaultUrl: '${keyVaultUri}secrets/${citrixSecretsNames.clientId}'
      }
    ]
  : (!empty(citrixClientId)
      ? [
          {
            name: secretAliases.clientId
            value: citrixClientId
          }
        ]
      : [])
var clientSecretSecrets = useKeyVaultReferences
  ? [
      {
        name: secretAliases.clientSecret
        identity: 'system'
        keyVaultUrl: '${keyVaultUri}secrets/${citrixSecretsNames.clientSecret}'
      }
    ]
  : (!empty(citrixClientSecret)
      ? [
          {
            name: secretAliases.clientSecret
            value: citrixClientSecret
          }
        ]
      : [])
var mcpBearerTokenSecrets = useKeyVaultReferences
  ? [
      {
        name: secretAliases.mcpBearerToken
        identity: 'system'
        keyVaultUrl: '${keyVaultUri}secrets/${mcpBearerTokenSecretName}'
      }
    ]
  : (!empty(mcpBearerToken)
      ? [
          {
            name: secretAliases.mcpBearerToken
            value: mcpBearerToken
          }
        ]
      : [])
var containerSecrets = concat(customerIdSecrets, clientIdSecrets, clientSecretSecrets, mcpBearerTokenSecrets)
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (useKeyVaultReferences) {
  name: keyVaultName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: managedEnvironmentName
  location: location
  tags: tags
  properties: {}
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'
        }
      ]
      secrets: containerSecrets
    }
    template: {
      containers: [
        {
          name: 'citrix-mcp'
          image: containerImage
          env: [
            {
              name: 'NODE_ENV'
              value: 'production'
            }
            {
              name: 'PORT'
              value: '3000'
            }
            {
              name: 'CITRIX_CUSTOMER_ID'
              secretRef: secretAliases.customerId
            }
            {
              name: 'CITRIX_CLIENT_ID'
              secretRef: secretAliases.clientId
            }
            {
              name: 'CITRIX_CLIENT_SECRET'
              secretRef: secretAliases.clientSecret
            }
            {
              name: 'MCP_BEARER_TOKEN'
              secretRef: secretAliases.mcpBearerToken
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerApp.id, 'citrix-mcp-acr-pull')
  scope: acr
  properties: {
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useKeyVaultReferences) {
  name: guid(keyVault.id, containerApp.id, 'citrix-mcp-keyvault-secrets-user')
  scope: keyVault
  properties: {
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppId string = containerApp.id
output managedEnvironmentId string = managedEnvironment.id

// Wire-up notes:
// - Call this module from infra\bicep\main.bicep when the future -DeployCitrixMcp flag is added.
// - Use containerAppFqdn to replace CITRIX_MCP_URL_PLACEHOLDER in sre-config\connectors\citrix-mcp.yaml.
// - Optionally deploy citrix-mcp-keyvault.bicep first so this module can consume Key Vault-backed secrets.
