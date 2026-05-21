// =============================================================================
// App Service Module
// =============================================================================
// Deploys a Linux App Service Plan and Node.js web application for the
// multi-stack Azure demo flow.
// =============================================================================

@description('Name of the App Service web app')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Application Insights connection string for the web app')
param appInsightsConnectionString string

@secure()
@description('Optional Cosmos DB endpoint injected into app settings')
param cosmosEndpoint string = ''

@secure()
@description('Optional SQL connection string injected into app settings')
param sqlConnectionString string = ''

var planName = 'plan-${name}'
var baseAppSettings = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: '~20'
  }
  {
    name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
    value: 'false'
  }
  {
    name: 'NODE_ENV'
    value: 'production'
  }
]
var optionalAppSettings = concat(
  empty(cosmosEndpoint)
    ? []
    : [
        {
          name: 'Cosmos__Endpoint'
          value: cosmosEndpoint
        }
      ],
  empty(sqlConnectionString)
    ? []
    : [
        {
          name: 'Sql__ConnectionString'
          value: sqlConnectionString
        }
      ]
)

// =============================================================================
// RESOURCES
// =============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    size: 'B1'
    family: 'B'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      appSettings: concat(baseAppSettings, optionalAppSettings)
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output appServiceUrl string = 'https://${webApp.properties.defaultHostName}'
output appServiceId string = webApp.id
output appServicePlanId string = appServicePlan.id

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployMultiStack)`:
//   module appService 'modules/app-service.bicep' = if (deployMultiStack) {
//     scope: resourceGroup
//     name: 'deploy-app-service'
//     params: {
//       name: names.appService
//       location: location
//       tags: tags
//       appInsightsConnectionString: appInsights.outputs.connectionString
//       cosmosEndpoint: cosmosDb.outputs.cosmosEndpoint
//       sqlConnectionString: sqlDatabase.outputs.sqlConnectionString
//     }
//   }
