// =============================================================================
// Azure SQL Database Module
// =============================================================================
// Deploys an Azure SQL logical server and S0 database for subscriber and activation demo data
// to make DTU saturation easy to demonstrate.
// =============================================================================

@description('Name of the Azure SQL logical server')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Administrator login for the SQL server')
param adminLogin string

@secure()
@description('Administrator password for the SQL server')
param adminPassword string

var databaseName = 'movistar-bss-db'

// =============================================================================
// RESOURCES
// =============================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name: 'S0'
    tier: 'Standard'
    capacity: 10
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = databaseName

@secure()
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};Persist Security Info=False;User ID=${adminLogin};Password=${adminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployMultiStack)`:
//   module sqlDatabase 'modules/sql-database.bicep' = if (deployMultiStack) {
//     scope: resourceGroup
//     name: 'deploy-sql-database'
//     params: {
//       name: names.sql
//       location: location
//       tags: tags
//       adminLogin: sqlAdminLogin
//       adminPassword: sqlAdminPassword
//     }
//   }
