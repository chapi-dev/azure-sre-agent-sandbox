// =============================================================================
// Azure Virtual Desktop Monitoring Module
// =============================================================================
// Enables Azure Monitor diagnostic settings for the Azure Virtual Desktop host
// pool, workspace, and application group resources.
// =============================================================================

@description('Name of the Azure Virtual Desktop host pool to monitor')
param hostPoolName string

@description('Name of the Azure Virtual Desktop workspace to monitor')
param workspaceName string

@description('Name of the Azure Virtual Desktop application group to monitor')
param applicationGroupName string

@description('Resource ID of the Log Analytics workspace that receives diagnostics')
param logAnalyticsWorkspaceId string

var hostPoolDiagnosticCategories = [
  'Checkpoint'
  'Error'
  'Management'
  'Connection'
  'HostRegistration'
  'AgentHealthStatus'
  'NetworkData'
  'SessionHostManagement'
]

// Workspace and application group resources only support a subset of the host
// pool categories, so use the intersection that deploys cleanly.
var workspaceDiagnosticCategories = [
  'Checkpoint'
  'Error'
  'Management'
]

var applicationGroupDiagnosticCategories = [
  'Checkpoint'
  'Error'
  'Management'
]

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' existing = {
  name: hostPoolName
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-08-preview' existing = {
  name: workspaceName
}

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2024-04-08-preview' existing = {
  name: applicationGroupName
}

// =============================================================================
// RESOURCES
// =============================================================================

resource hostPoolDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: hostPool
  name: 'send-avd-logs'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [for category in hostPoolDiagnosticCategories: {
      category: category
      enabled: true
    }]
  }
}

resource workspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: workspace
  name: 'send-avd-logs'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [for category in workspaceDiagnosticCategories: {
      category: category
      enabled: true
    }]
  }
}

resource applicationGroupDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: applicationGroup
  name: 'send-avd-logs'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [for category in applicationGroupDiagnosticCategories: {
      category: category
      enabled: true
    }]
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output diagnosticSettingsId string = hostPoolDiagnostics.id

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployAvd)`:
//   module avdMonitoring 'modules/avd-monitoring.bicep' = if (deployAvd) {
//     scope: resourceGroup
//     name: 'deploy-avd-monitoring'
//     params: { ... }
//   }
