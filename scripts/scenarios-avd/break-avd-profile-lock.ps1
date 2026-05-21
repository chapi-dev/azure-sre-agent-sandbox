<#
.SYNOPSIS
    Creates a simulated FSLogix profile lock file on a session host.

.DESCRIPTION
    Uses az vm run-command invoke to create a .lock file under an FSLogix-style
    profile path. If the lab doesn't use a real FSLogix profile share, this is a
    simulated scenario to reproduce the troubleshooting pattern.

.PARAMETER ResourceGroupName
    Resource group containing the AVD session hosts.

.PARAMETER SessionHostName
    Optional session host VM name. If omitted, the first discovered host is used.

.EXAMPLE
    .\break-avd-profile-lock.ps1 -ResourceGroupName rg-srelab-eastus2
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
$profileRoot = 'C:\FSLogix\Profiles\demo-user'
$lockPath = Join-Path -Path $profileRoot -ChildPath 'Profile_demo.vhdx.lock'
New-Item -Path $profileRoot -ItemType Directory -Force | Out-Null
Set-Content -Path $lockPath -Value 'SIMULATED FSLogix lock file created for the Azure SRE Agent demo lab.'
Get-Item -Path $lockPath | Select-Object FullName, Length, CreationTimeUtc
'@

if ($PSCmdlet.ShouldProcess($targetHost, 'Create simulated FSLogix profile lock')) {
    az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $targetHost `
        --command-id RunPowerShellScript `
        --scripts $script `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the simulated FSLogix lock on '$targetHost'."
    }

    Write-Host "✅ Created simulated FSLogix lock on $targetHost" -ForegroundColor Green
    Write-Host "   This is a mock scenario if a real FSLogix share is not configured." -ForegroundColor Yellow
}
