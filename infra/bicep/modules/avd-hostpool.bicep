// =============================================================================
// Azure Virtual Desktop Host Pool Module
// =============================================================================
// Deploys a pooled Azure Virtual Desktop host pool with Windows 11 Enterprise
// multi-session session hosts, a desktop application group, and a workspace.
// The session host bootstrap follows the Microsoft quickstart pattern that uses
// AADLoginForWindows plus DSC AddSessionHost for host pool registration.
// =============================================================================

@description('Name of the Azure Virtual Desktop host pool')
param name string

@description('Azure region for deployment')
param location string

@description('Tags to apply to resources')
param tags object

@description('Host pool type for the deployment')
@allowed([
  'Pooled'
])
param hostPoolType string = 'Pooled'

@description('Subnet resource ID for the AVD session hosts')
param vnetSubnetId string

@description('Number of session hosts to deploy')
@minValue(1)
param sessionHostCount int = 2

@description('VM size for the session hosts')
param vmSize string = 'Standard_D2s_v3'

@description('Local administrator username for the session hosts')
param adminUsername string

@secure()
@description('Local administrator password for the session hosts')
param adminPassword string

@description('Log Analytics workspace resource ID used by the wider AVD monitoring flow')
param workspaceId string

@description('Registration token expiration time in UTC')
param registrationTokenExpiration string = dateTimeAdd(utcNow('u'), 'P1D')

@description('Microsoft-hosted DSC package used to register session hosts to the host pool')
#disable-next-line no-hardcoded-env-urls
param artifactsLocation string = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02774.414.zip'

var workloadName = replace(name, 'hp-', '')
var avdWorkspaceName = 'avdws-${workloadName}'
var avdApplicationGroupName = 'avdag-${workloadName}'
var sessionHostNames = [for i in range(0, sessionHostCount): 'vm-avd-${workloadName}-${i + 1}']
var customRdpProperty = 'targetisaadjoined:i:1;audiocapturemode:i:1;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;redirectcomports:i:1;redirectsmartcards:i:1;redirectwebauthn:i:1;drivestoredirect:s:*;devicestoredirect:s:*;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;use multimon:i:1;'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  scope: resourceGroup(split(workspaceId, '/')[2], split(workspaceId, '/')[4])
  name: split(workspaceId, '/')[8]
}

var commonTags = union(tags, {
  module: 'avd'
  avdWorkload: workloadName
  logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
})

// =============================================================================
// RESOURCES
// =============================================================================

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' = {
  name: name
  location: location
  tags: union(commonTags, {
    avdRole: 'host-pool'
  })
  properties: {
    friendlyName: name
    description: 'Pooled Azure Virtual Desktop host pool for the SRE demo lab.'
    hostPoolType: hostPoolType
    maxSessionLimit: 2
    loadBalancerType: 'BreadthFirst'
    validationEnvironment: false
    preferredAppGroupType: 'Desktop'
    publicNetworkAccess: 'Enabled'
    customRdpProperty: customRdpProperty
    directUDP: 'Default'
    managedPrivateUDP: 'Default'
    managementType: 'Standard'
    publicUDP: 'Default'
    relayUDP: 'Default'
    startVMOnConnect: true
    registrationInfo: {
      expirationTime: registrationTokenExpiration
      registrationTokenOperation: 'Update'
    }
  }
}

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2024-04-08-preview' = {
  name: avdApplicationGroupName
  location: location
  tags: union(commonTags, {
    avdRole: 'application-group'
  })
  properties: {
    applicationGroupType: 'Desktop'
    friendlyName: avdApplicationGroupName
    description: 'Desktop application group for ${name}.'
    hostPoolArmPath: hostPool.id
  }
}

resource workspace 'Microsoft.DesktopVirtualization/workspaces@2024-04-08-preview' = {
  name: avdWorkspaceName
  location: location
  tags: union(commonTags, {
    avdRole: 'workspace'
  })
  properties: {
    friendlyName: avdWorkspaceName
    description: 'Azure Virtual Desktop workspace for ${name}.'
    publicNetworkAccess: 'Enabled'
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

resource networkInterfaces 'Microsoft.Network/networkInterfaces@2024-01-01' = [for (sessionHostName, i) in sessionHostNames: {
  name: '${sessionHostName}-nic'
  location: location
  tags: union(commonTags, {
    avdRole: 'session-host-nic'
    avdSessionHostName: sessionHostName
    avdInstance: string(i + 1)
  })
  properties: {
    enableAcceleratedNetworking: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnetSubnetId
          }
        }
      }
    ]
  }
}]

resource sessionHosts 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (sessionHostName, i) in sessionHostNames: {
  name: sessionHostName
  location: location
  tags: union(commonTags, {
    avdRole: 'session-host'
    avdHostPool: name
    avdSessionHostName: sessionHostName
    avdInstance: string(i + 1)
  })
  properties: {
    licenseType: 'Windows_Client'
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-23h2-avd'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces[i].id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    osProfile: {
      computerName: sessionHostName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}]

resource aadLoginExtensions 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (sessionHostName, i) in sessionHostNames: {
  parent: sessionHosts[i]
  name: 'AADLoginForWindows'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: false
  }
}]

resource avdRegistrationExtensions 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (sessionHostName, i) in sessionHostNames: {
  parent: sessionHosts[i]
  name: 'MicrosoftPowershellDSC'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.83'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: artifactsLocation
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: hostPool.name
        aadJoin: true
      }
    }
    protectedSettings: {
      properties: {
        registrationInfoToken: hostPool.listRegistrationTokens().value[0].token
      }
    }
  }
  dependsOn: [
    aadLoginExtensions[i]
  ]
}]

// =============================================================================
// OUTPUTS
// =============================================================================

output hostPoolId string = hostPool.id
output hostPoolName string = hostPool.name
output workspaceResourceId string = workspace.id
output applicationGroupId string = applicationGroup.id
output sessionHostNames array = sessionHostNames

// =============================================================================
// WIRE-UP NOTES (for main.bicep integration agent)
// =============================================================================
// Call this module from main.bicep guarded by `if (deployAvd)`:
//   module avd 'modules/avd-hostpool.bicep' = if (deployAvd) {
//     scope: resourceGroup
//     name: 'deploy-avd'
//     params: { ... }
//   }
