<#
.SYNOPSIS
    Stops the Azure Virtual Desktop agent boot loader service on a session host.

.DESCRIPTION
    Uses az vm run-command invoke to stop the RDAgentBootLoader service on the
    specified session host. If -SessionHostName is omitted, the script selects
    the first AVD session host it can discover in the resource group.

.PARAMETER ResourceGroupName
    Resource group containing the AVD session hosts.

.PARAMETER SessionHostName
    Optional session host VM name. If omitted, the first discovered host is used.

.EXAMPLE
    .\break-avd-agent-stopped.ps1 -ResourceGroupName rg-srelab-eastus2
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$SessionHostName
)

$ErrorActionPreference = 'Stop'

function Get-AvdSessionHosts {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName
    )

    $raw = az vm list --resource-group $ResourceGroupName --output json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list VMs in $ResourceGroupName. $raw"
    }

    $vms = $raw | ConvertFrom-Json
    return @($vms | Where-Object {
            $isTagged = $null -ne $_.tags -and $_.tags.PSObject.Properties.Name -contains 'avdRole' -and $_.tags.avdRole -eq 'session-host'
            $isNamed = $_.name -like 'vm-avd-*'
            $isTagged -or $isNamed
        } | Sort-Object -Property name)
}

$targetHost = $SessionHostName
if ([string]::IsNullOrWhiteSpace($targetHost)) {
    $discoveredHost = Get-AvdSessionHosts -ResourceGroupName $ResourceGroupName | Select-Object -First 1
    $targetHost = $discoveredHost.name
}

if ([string]::IsNullOrWhiteSpace($targetHost)) {
    throw "No AVD session hosts were found in resource group '$ResourceGroupName'."
}

$script = @'
Stop-Service -Name RDAgentBootLoader -Force -ErrorAction Stop
Get-Service -Name RDAgentBootLoader | Select-Object Name, Status, StartType
'@

if ($PSCmdlet.ShouldProcess($targetHost, 'Stop RDAgentBootLoader')) {
    az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $targetHost `
        --command-id RunPowerShellScript `
        --scripts $script `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stop RDAgentBootLoader on '$targetHost'."
    }

    Write-Host "✅ Stopped RDAgentBootLoader on $targetHost" -ForegroundColor Green
}
