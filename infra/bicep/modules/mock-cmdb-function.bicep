// =============================================================================
// Mock CMDB Function App Module
// =============================================================================
// Deploys a lightweight Linux Consumption Function App placeholder that can host
// mock CMDB endpoints for Module D plugin demos.
// =============================================================================

@description('Name of the Function App.')
param name string

@description('Azure region for deployment.')
param location string

@description('Tags to apply to resources.')
param tags object

@description('Application Insights connection string for the Function App.')
param appInsightsConnectionString string

@description('Resource ID of the storage account used by the Function runtime.')
param storageAccountId string

@description('Name of the storage account used by the Function runtime.')
param storageAccountName string

var hostingPlanName = '${name}-plan'
var storageApiVersion = '2023-05-01'
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccountId, storageApiVersion).keys[0].value}'
var cmdbSeedData = '[{"serviceName":"order-service","owner":"team-orders@contoso.com","criticality":"high","runbook":"order-service-oom.md","dependencies":["inventory-service","payment-service"]},{"serviceName":"inventory-service","owner":"team-inventory@contoso.com","criticality":"medium","runbook":"inventory-api-latency.md","dependencies":["catalog-db"]}]'

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    reserved: true
    serverFarmId: hostingPlan.id
    siteConfig: {
      linuxFxVersion: 'Node|20'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~20'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(replace(name, '-', ''))
        }
        {
          name: 'CMDB_DATA_JSON'
          value: cmdbSeedData
        }
        {
          name: 'CMDB_ROUTE_PREFIX'
          value: '/api/services'
        }
      ]
    }
  }
}

resource functionAppHost 'Microsoft.Web/sites/host@2022-09-01' existing = {
  parent: functionApp
  name: 'default'
}

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api'
@secure()
#disable-next-line outputs-should-not-contain-secrets
output functionKey string = functionAppHost.listKeys().functionKeys.default

// =============================================================================
// Integration note
// =============================================================================
// Expected main.bicep usage:
// module mockCmdbFunction 'modules/mock-cmdb-function.bicep' = if (deploySkills) {
//   name: 'mock-cmdb-function'
//   params: {
//     name: 'func-cmdb-${uniqueSuffix}'
//     location: location
//     tags: tags
//     appInsightsConnectionString: appInsights.outputs.connectionString
//     storageAccountId: storageAccount.id
//     storageAccountName: storageAccount.name
//   }
// }