// =============================================================================
// Azure SRE Agent Demo Lab - Main Bicep Template
// =============================================================================
// This template deploys an AKS cluster with a multi-pod sample application,
// along with supporting infrastructure for demonstrating Azure SRE Agent
// capabilities for diagnostics and troubleshooting.
// =============================================================================

targetScope = 'subscription'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Name of the workload (used for naming resources)')
@minLength(3)
@maxLength(10)
param workloadName string = 'srelab'

@description('Azure region for deployment. Must be a region supporting SRE Agent (East US 2, Sweden Central, Australia East)')
@allowed([
  'eastus2'
  'swedencentral'
  'australiaeast'
])
param location string = 'eastus2'

@description('Deploy full observability stack (Managed Grafana, Prometheus)')
param deployObservability bool = true

@description('Deploy baseline Azure Monitor alert rules for AKS and app telemetry')
param deployAlerts bool = false

@description('Deploy Azure SRE Agent for AI-powered diagnostics and remediation')
param deploySreAgent bool = true

@description('Deploy default Action Group for alert notifications and incident routing')
param deployActionGroup bool = false

@description('Action Group short name (max 12 characters)')
@maxLength(12)
param actionGroupShortName string = 'srelabops'

@secure()
@description('Optional webhook/Logic App callback URL for default Action Group incident routing')
param incidentWebhookServiceUri string = ''

@description('Optional action group resource IDs to notify when alerts fire')
param alertActionGroupIds array = []

@description('AKS Kubernetes version (empty = latest stable)')
param kubernetesVersion string = ''

@description('AKS system node pool VM size')
@allowed([
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2as_v5'
  'Standard_D4as_v5'
  'Standard_D2s_v6'
  'Standard_D4s_v6'
  'Standard_D2as_v6'
  'Standard_D4as_v6'
])
param systemNodeVmSize string = 'Standard_D2s_v3'

@description('AKS user node pool VM size for workloads')
@allowed([
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D2s_v5'
  'Standard_D4s_v5'
  'Standard_D2as_v5'
  'Standard_D4as_v5'
  'Standard_D2s_v6'
  'Standard_D4s_v6'
  'Standard_D2as_v6'
  'Standard_D4as_v6'
])
param userNodeVmSize string = 'Standard_D2s_v3'

@description('System node pool node count')
@minValue(1)
@maxValue(5)
param systemNodeCount int = 2

@description('User node pool node count')
@minValue(1)
@maxValue(10)
param userNodeCount int = 3

@description('Tags to apply to all resources')
param tags object = {
  workload: 'sre-agent-demo'
  environment: 'sandbox'
  managedBy: 'bicep'
  purpose: 'demonstration'
}

@description('Deploy Module A: multi-stack Azure (App Service + Cosmos + SQL + Function + Storage)')
param deployMultiStack bool = false

@description('Deploy Module B: Azure Virtual Desktop host pool and session hosts')
param deployAvd bool = false

@description('Deploy Module C: Citrix DaaS MCP server (Container App)')
param deployCitrixMcp bool = false

@description('Deploy Module D: Skills + Hooks infrastructure (mock CMDB Function + audit Storage)')
param deploySkillsAndHooks bool = false

@description('Deploy Module F: Governance — cost Workbook + AAU alert')
param deployGovernance bool = false

@secure()
@description('Admin password for AVD session hosts and Azure SQL (Module B + A)')
param adminPassword string = ''

@description('Admin username for AVD/SQL')
param adminUsername string = 'srelab-admin'

@secure()
@description('Citrix Cloud client secret (Module C)')
param citrixClientSecret string = ''

@description('Citrix Cloud customer ID (Module C)')
param citrixCustomerId string = ''

@description('Citrix Cloud client ID (Module C)')
param citrixClientId string = ''

@secure()
@description('Bearer token for the Citrix MCP server (Module C). Generate a random string.')
param mcpBearerToken string = ''

// =============================================================================
// VARIABLES
// =============================================================================

var resourceGroupName = 'rg-${workloadName}-${location}'
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupName)

// Naming convention for resources
var names = {
  aks: 'aks-${workloadName}'
  acr: 'acr${workloadName}${take(uniqueSuffix, 6)}'
  logAnalytics: 'log-${workloadName}'
  appInsights: 'appi-${workloadName}'
  grafana: 'grafana-${workloadName}-${take(uniqueSuffix, 6)}'
  prometheus: 'prometheus-${workloadName}'
  keyVault: 'kv-${workloadName}-${take(uniqueSuffix, 6)}'
  managedIdentity: 'id-${workloadName}'
  vnet: 'vnet-${workloadName}'
  sreAgent: 'sre-${workloadName}'
  appService: 'app-${workloadName}'
  appServicePlan: 'asp-${workloadName}'
  cosmos: 'cosmos-${workloadName}-${take(uniqueSuffix, 6)}'
  sqlServer: 'sql-${workloadName}-${take(uniqueSuffix, 6)}'
  functionApp: 'func-${workloadName}-${take(uniqueSuffix, 6)}'
  functionStorage: 'stfunc${workloadName}${take(uniqueSuffix, 6)}'
  storageExtra: 'st${workloadName}${take(uniqueSuffix, 6)}'
  avdHostPool: 'hp-${workloadName}'
  avdWorkspace: 'avdws-${workloadName}'
  avdAppGroup: 'avdag-${workloadName}'
  citrixContainerApp: 'ca-citrix-mcp-${workloadName}'
  citrixMcpEnv: 'cae-${workloadName}'
  mockCmdb: 'func-cmdb-${workloadName}-${take(uniqueSuffix, 6)}'
  auditStorage: 'staudit${workloadName}${take(uniqueSuffix, 6)}'
  costWorkbook: 'wb-sre-cost-${workloadName}'
  costAlert: 'alert-sre-aau-${workloadName}'
}

// =============================================================================
// RESOURCE GROUP
// =============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// =============================================================================
// MODULES
// =============================================================================

// Log Analytics Workspace (required for AKS monitoring and SRE Agent)
module logAnalytics 'modules/log-analytics.bicep' = {
  scope: resourceGroup
  name: 'deploy-log-analytics'
  params: {
    name: names.logAnalytics
    location: location
    tags: tags
    retentionInDays: 30
  }
}

// Application Insights (for application-level telemetry)
module appInsights 'modules/app-insights.bicep' = {
  scope: resourceGroup
  name: 'deploy-app-insights'
  params: {
    name: names.appInsights
    location: location
    tags: tags
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

// Virtual Network for AKS
module network 'modules/network.bicep' = {
  scope: resourceGroup
  name: 'deploy-network'
  params: {
    vnetName: names.vnet
    location: location
    tags: tags
    addressPrefix: '10.0.0.0/16'
    aksSubnetPrefix: '10.0.0.0/22'
    servicesSubnetPrefix: '10.0.4.0/24'
  }
}

// Azure Container Registry
module containerRegistry 'modules/container-registry.bicep' = {
  scope: resourceGroup
  name: 'deploy-acr'
  params: {
    name: names.acr
    location: location
    tags: tags
    sku: 'Basic'
  }
}

// Azure Kubernetes Service
module aks 'modules/aks.bicep' = {
  scope: resourceGroup
  name: 'deploy-aks'
  params: {
    name: names.aks
    location: location
    tags: tags
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: systemNodeVmSize
    userNodeVmSize: userNodeVmSize
    systemNodeCount: systemNodeCount
    userNodeCount: userNodeCount
    vnetSubnetId: network.outputs.aksSubnetId
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    acrId: containerRegistry.outputs.acrId
  }
}

// Key Vault for secrets management
module keyVault 'modules/key-vault.bicep' = {
  scope: resourceGroup
  name: 'deploy-keyvault'
  params: {
    name: names.keyVault
    location: location
    tags: tags
    enableRbacAuthorization: true
  }
}

// Azure SRE Agent (optional)
module sreAgent 'modules/sre-agent.bicep' = if (deploySreAgent) {
  scope: resourceGroup
  name: 'deploy-sre-agent'
  params: {
    agentName: names.sreAgent
    location: location
    tags: tags
    accessLevel: 'High'
    appInsightsAppId: appInsights.outputs.appId
    appInsightsConnectionString: appInsights.outputs.connectionString
    uniqueSuffix: uniqueSuffix
    managedResourceIds: [
      aks.outputs.aksId
    ]
  }
}

// Observability Stack - Managed Grafana and Prometheus (optional)
module observability 'modules/observability.bicep' = if (deployObservability) {
  scope: resourceGroup
  name: 'deploy-observability'
  params: {
    grafanaName: names.grafana
    prometheusName: names.prometheus
    location: location
    tags: tags
    aksClusterId: aks.outputs.aksId
  }
}

// Module A - Multi-stack Azure (optional)
// Provide adminPassword at deploy time when deployMultiStack = true because Azure SQL requires a non-empty admin password.
module cosmosDb 'modules/cosmos-db.bicep' = if (deployMultiStack) {
  scope: resourceGroup
  name: 'deploy-cosmos-db'
  params: {
    name: names.cosmos
    location: location
    tags: tags
  }
  dependsOn: [
    logAnalytics
    appInsights
  ]
}

module sqlDatabase 'modules/sql-database.bicep' = if (deployMultiStack) {
  scope: resourceGroup
  name: 'deploy-sql-database'
  params: {
    name: names.sqlServer
    location: location
    tags: tags
    adminLogin: adminUsername
    adminPassword: adminPassword
  }
  dependsOn: [
    logAnalytics
    appInsights
  ]
}

module functionApp 'modules/function-app.bicep' = if (deployMultiStack) {
  scope: resourceGroup
  name: 'deploy-function-app'
  params: {
    name: names.functionApp
    location: location
    tags: tags
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
}

module storageExtra 'modules/storage-extra.bicep' = if (deployMultiStack) {
  scope: resourceGroup
  name: 'deploy-storage-extra'
  params: {
    name: names.storageExtra
    location: location
    tags: tags
  }
  dependsOn: [
    logAnalytics
    appInsights
  ]
}

module appService 'modules/app-service.bicep' = if (deployMultiStack) {
  scope: resourceGroup
  name: 'deploy-app-service'
  params: {
    name: names.appService
    location: location
    tags: tags
    appInsightsConnectionString: appInsights.outputs.connectionString
    cosmosEndpoint: cosmosDb!.outputs.cosmosEndpoint
    sqlConnectionString: 'Server=tcp:${sqlDatabase!.outputs.sqlServerFqdn},1433;Initial Catalog=movistar-bss-db;Persist Security Info=False;User ID=${adminUsername};Password=${adminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}

// Module B - Azure Virtual Desktop (optional)
// Provide adminPassword at deploy time when deployAvd = true because Bicep cannot assert non-empty secure strings here.
module avd 'modules/avd-hostpool.bicep' = if (deployAvd) {
  scope: resourceGroup
  name: 'deploy-avd'
  params: {
    name: names.avdHostPool
    location: location
    tags: tags
    vnetSubnetId: network.outputs.servicesSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

module avdMonitoring 'modules/avd-monitoring.bicep' = if (deployAvd) {
  scope: resourceGroup
  name: 'deploy-avd-monitoring'
  params: {
    hostPoolName: avd!.outputs.hostPoolName
    workspaceName: last(split(avd!.outputs.workspaceResourceId, '/'))
    applicationGroupName: last(split(avd!.outputs.applicationGroupId, '/'))
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// Module C - Citrix MCP (optional)
module citrixMcpKeyVault 'modules/citrix-mcp-keyvault.bicep' = if (deployCitrixMcp) {
  scope: resourceGroup
  name: 'deploy-citrix-mcp-keyvault'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    citrixCustomerId: citrixCustomerId
    citrixClientId: citrixClientId
    citrixClientSecret: citrixClientSecret
    mcpBearerToken: mcpBearerToken
  }
}

module citrixMcpContainer 'modules/citrix-mcp-container.bicep' = if (deployCitrixMcp) {
  scope: resourceGroup
  name: 'deploy-citrix-mcp-container'
  params: {
    name: names.citrixContainerApp
    location: location
    tags: tags
    acrId: containerRegistry.outputs.acrId
    keyVaultId: keyVault.outputs.keyVaultId
  }
  dependsOn: [
    citrixMcpKeyVault
  ]
}

// Module D - Skills and Hooks (optional)
// deploySkillsAndHooks assumes deploySreAgent = true so the audit account can grant the SRE Agent identity write access.
// Reuse storage-extra.bicep for the mock CMDB Function runtime because this subscription-scoped template can't inline RG-scoped resources.
module mockCmdbStorage 'modules/storage-extra.bicep' = if (deploySkillsAndHooks) {
  scope: resourceGroup
  name: 'deploy-mock-cmdb-storage'
  params: {
    name: names.functionStorage
    location: location
    tags: union(tags, {
      module: 'skills-hooks'
      component: 'mock-cmdb-storage'
    })
  }
}

module mockCmdbFunction 'modules/mock-cmdb-function.bicep' = if (deploySkillsAndHooks) {
  scope: resourceGroup
  name: 'deploy-mock-cmdb-function'
  params: {
    name: names.mockCmdb
    location: location
    tags: tags
    appInsightsConnectionString: appInsights.outputs.connectionString
    storageAccountId: mockCmdbStorage!.outputs.storageAccountId
    storageAccountName: mockCmdbStorage!.outputs.storageAccountName
  }
}

module auditStorage 'modules/audit-storage.bicep' = if (deploySkillsAndHooks) {
  scope: resourceGroup
  name: 'deploy-audit-storage'
  params: {
    name: names.auditStorage
    location: location
    tags: tags
    sreAgentPrincipalId: sreAgent!.outputs.managedIdentityPrincipalId
  }
}

module defaultActionGroup 'modules/action-group.bicep' = if (deployActionGroup) {
  scope: resourceGroup
  name: 'deploy-default-action-group'
  params: {
    name: 'ag-${workloadName}'
    location: location
    tags: tags
    shortName: actionGroupShortName
    webhookServiceUri: incidentWebhookServiceUri
  }
}

var effectiveAlertActionGroupIds = deployActionGroup
  ? concat(alertActionGroupIds, [defaultActionGroup!.outputs.actionGroupId])
  : alertActionGroupIds

module alerts 'modules/alerts.bicep' = if (deployAlerts) {
  scope: resourceGroup
  name: 'deploy-alerts'
  params: {
    namePrefix: 'alert-${workloadName}'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    appNamespace: 'movistar'
    actionGroupIds: effectiveAlertActionGroupIds
  }
}

// Module F - Governance (optional)
module costWorkbook 'modules/cost-workbook.bicep' = if (deployGovernance) {
  scope: resourceGroup
  name: 'deploy-cost-workbook'
  params: {
    name: names.costWorkbook
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

module costAlerts 'modules/cost-alerts.bicep' = if (deployGovernance) {
  scope: resourceGroup
  name: 'deploy-cost-alerts'
  params: {
    name: names.costAlert
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    dailyAauThreshold: 50
    actionGroupIds: effectiveAlertActionGroupIds
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output resourceGroupName string = resourceGroup.name
output aksClusterName string = aks.outputs.aksName
output aksClusterFqdn string = aks.outputs.aksFqdn
output acrLoginServer string = containerRegistry.outputs.loginServer
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output appInsightsId string = appInsights.outputs.appInsightsId
output appInsightsConnectionString string = appInsights.outputs.connectionString
output keyVaultUri string = keyVault.outputs.vaultUri
output grafanaDashboardUrl string = deployObservability ? observability!.outputs.grafanaEndpoint : ''
output azureMonitorWorkspaceId string = deployObservability ? observability!.outputs.azureMonitorWorkspaceId : ''
output prometheusDataCollectionEndpointId string = deployObservability
  ? observability!.outputs.dataCollectionEndpointId
  : ''
output prometheusDataCollectionRuleId string = deployObservability ? observability!.outputs.dataCollectionRuleId : ''
output prometheusDcrAssociationId string = deployObservability
  ? observability!.outputs.dataCollectionRuleAssociationId
  : ''
output defaultActionGroupId string = deployActionGroup ? defaultActionGroup!.outputs.actionGroupId : ''
output defaultActionGroupHasWebhook bool = deployActionGroup ? defaultActionGroup!.outputs.hasWebhookReceiver : false
output podRestartAlertId string = deployAlerts ? alerts!.outputs.podRestartAlertId : ''
output http5xxAlertId string = deployAlerts ? alerts!.outputs.http5xxAlertId : ''
output podFailureAlertId string = deployAlerts ? alerts!.outputs.podFailureAlertId : ''
output crashLoopOomAlertId string = deployAlerts ? alerts!.outputs.crashLoopOomAlertId : ''
output sreAgentId string = deploySreAgent ? sreAgent!.outputs.agentId : ''
output sreAgentPortalUrl string = deploySreAgent ? sreAgent!.outputs.agentPortalUrl : ''
output sreAgentName string = deploySreAgent ? sreAgent!.outputs.agentName : ''
output sreAgentManagedIdentityId string = deploySreAgent ? sreAgent!.outputs.managedIdentityId : ''
output sreAgentManagedIdentityPrincipalId string = deploySreAgent ? sreAgent!.outputs.managedIdentityPrincipalId : ''
output appServiceUrl string = deployMultiStack ? appService!.outputs.appServiceUrl : ''
output cosmosEndpoint string = deployMultiStack ? cosmosDb!.outputs.cosmosEndpoint : ''
output sqlServerFqdn string = deployMultiStack ? sqlDatabase!.outputs.sqlServerFqdn : ''
output functionAppDefaultHostName string = deployMultiStack ? functionApp!.outputs.functionAppDefaultHostName : ''
output storageExtraName string = deployMultiStack ? storageExtra!.outputs.storageAccountName : ''
output avdHostPoolName string = deployAvd ? avd!.outputs.hostPoolName : ''
output avdWorkspaceName string = deployAvd ? last(split(avd!.outputs.workspaceResourceId, '/')) : ''
output avdApplicationGroupId string = deployAvd ? avd!.outputs.applicationGroupId : ''
output citrixMcpContainerAppFqdn string = deployCitrixMcp ? citrixMcpContainer!.outputs.containerAppFqdn : ''
output mockCmdbUrl string = deploySkillsAndHooks ? 'https://${mockCmdbFunction!.outputs.functionAppDefaultHostName}/api' : ''
output mockCmdbFunctionName string = deploySkillsAndHooks ? mockCmdbFunction!.outputs.functionAppName : ''
output auditStorageName string = deploySkillsAndHooks ? auditStorage!.outputs.storageAccountName : ''
output costWorkbookId string = deployGovernance ? costWorkbook!.outputs.workbookId : ''
output costAlertId string = deployGovernance ? costAlerts!.outputs.alertId : ''
