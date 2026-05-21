// =============================================================================
// Azure Virtual Desktop Application Group Module
// =============================================================================
// Deploys a desktop application group bound to an Azure Virtual Desktop host
// pool.
// =============================================================================

@description('Name of the Azure Virtual Desktop application group')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Resource ID of the Azure Virtual Desktop host pool')
param hostPoolArmPath string

@description('Application group type to deploy')
@allowed([
  'Desktop'
  'RemoteApp'
])
param applicationGroupType string = 'Desktop'

// =============================================================================
// RESOURCES
// =============================================================================

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2024-04-08-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    applicationGroupType: applicationGroupType
    friendlyName: name
    description: 'Azure Virtual Desktop application group bound to ${hostPoolArmPath}.'
    hostPoolArmPath: hostPoolArmPath
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

output applicationGroupId string = applicationGroup.id
output applicationGroupName string = applicationGroup.name

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployAvd)`:
//   module avdApplicationGroup 'modules/avd-application-group.bicep' = if (deployAvd) {
//     scope: resourceGroup
//     name: 'deploy-avd-application-group'
//     params: { ... }
//   }
