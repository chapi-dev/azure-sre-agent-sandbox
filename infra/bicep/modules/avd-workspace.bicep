// =============================================================================
// Azure Virtual Desktop Workspace Module
// =============================================================================
// Deploys an Azure Virtual Desktop workspace that groups one or more
// application groups for end-user assignment.
// =============================================================================

@description('Name of the Azure Virtual Desktop workspace')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Application group resource IDs to associate to the workspace')
param applicationGroupIds array

// =============================================================================
// RESOURCES
// =============================================================================

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-08-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    friendlyName: name
    description: 'Azure Virtual Desktop workspace for grouped application delivery.'
    publicNetworkAccess: 'Enabled'
    applicationGroupReferences: applicationGroupIds
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output workspaceId string = workspace.id
output workspaceName string = workspace.name

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployAvd)`:
//   module avdWorkspace 'modules/avd-workspace.bicep' = if (deployAvd) {
//     scope: resourceGroup
//     name: 'deploy-avd-workspace'
//     params: { ... }
//   }
