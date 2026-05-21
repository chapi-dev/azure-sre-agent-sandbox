<#
.SYNOPSIS
    Fills the session host OS disk with a 50 GB test file.

.DESCRIPTION
    Uses az vm run-command invoke to create C:\bloat.bin on the selected session
    host. If -SessionHostName is omitted, the script selects the first AVD
    session host it can discover in the resource group.

.PARAMETER ResourceGroupName
    Resource group containing the AVD session hosts.

.PARAMETER SessionHostName
    Optional session host VM name. If omitted, the first discovered host is used.

.EXAMPLE
    .\break-avd-disk-pressure.ps1 -ResourceGroupName rg-srelab-eastus2
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
if (Test-Path 'C:\bloat.bin') {
    Remove-Item 'C:\bloat.bin' -Force
}
fsutil file createnew C:\bloat.bin 50000000000 | Out-Null
Get-PSDrive -Name C | Select-Object Name, Used, Free
'@

if ($PSCmdlet.ShouldProcess($targetHost, 'Create 50 GB bloat file on C:')) {
    az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $targetHost `
        --command-id RunPowerShellScript `
        --scripts $script `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create C:\bloat.bin on '$targetHost'."
    }

    Write-Host "✅ Created C:\bloat.bin on $targetHost" -ForegroundColor Green
}
