// =============================================================================
// Cosmos DB Module
// =============================================================================
// Deploys a single-region Cosmos DB SQL API account, database, and container
// sized intentionally low to make RU throttling easy to demonstrate.
// =============================================================================

@description('Name of the Cosmos DB account')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

var databaseName = 'movistar-bss-db'
var containerName = 'plans-catalog'
var partitionKeyPath = '/category'

// =============================================================================
// RESOURCES
// =============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Enabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    disableKeyBasedMetadataWriteAccess: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource sqlDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    options: {}
  }
}

resource productsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: sqlDatabase
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: {
      throughput: 400
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosAccountId string = cosmosAccount.id
output cosmosDatabaseName string = databaseName
output cosmosContainerName string = containerName

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployMultiStack)`:
//   module cosmosDb 'modules/cosmos-db.bicep' = if (deployMultiStack) {
//     scope: resourceGroup
//     name: 'deploy-cosmos-db'
//     params: {
//       name: names.cosmos
//       location: location
//       tags: tags
//     }
//   }
