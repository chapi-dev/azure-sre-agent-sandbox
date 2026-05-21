<#
.SYNOPSIS
    Adds an NSG deny rule that blocks Azure Virtual Desktop outbound traffic.

.DESCRIPTION
    Creates a high-priority outbound deny rule to block TCP 443 traffic to the
    WindowsVirtualDesktop service tag. This simulates broken STA and broker
    connectivity for the AVD subnet or NIC protected by the NSG.

.PARAMETER ResourceGroupName
    Resource group containing the NSG.

.PARAMETER NsgName
    Name of the NSG to modify.

.EXAMPLE
    .\break-avd-nsg-block.ps1 -ResourceGroupName rg-srelab-eastus2 -NsgName nsg-avd
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$NsgName
)

$ErrorActionPreference = 'Stop'
$ruleName = 'deny-avd-sta-443'

$existingRule = az network nsg rule show `
    --resource-group $ResourceGroupName `
    --nsg-name $NsgName `
    --name $ruleName `
    --output json 2>$null | Out-String

if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingRule)) {
    Write-Host "ℹ️ Rule '$ruleName' already exists on NSG '$NsgName'." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($NsgName, 'Create outbound deny rule for WindowsVirtualDesktop:443')) {
    az network nsg rule create `
        --resource-group $ResourceGroupName `
        --nsg-name $NsgName `
        --name $ruleName `
        --priority 100 `
        --direction Outbound `
        --access Deny `
        --protocol Tcp `
        --source-address-prefixes '*' `
        --source-port-ranges '*' `
        --destination-address-prefixes WindowsVirtualDesktop `
        --destination-port-ranges 443 `
        --description 'Demo break: block outbound Azure Virtual Desktop traffic on TCP 443.' `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create '$ruleName' on NSG '$NsgName'."
    }

    Write-Host "✅ Added deny rule '$ruleName' to NSG '$NsgName'." -ForegroundColor Green
}
