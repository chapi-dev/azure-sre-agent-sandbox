<#
.SYNOPSIS
    Reverts the Azure Virtual Desktop demo break scenarios.

.DESCRIPTION
    Discovers AVD session hosts by tag or naming convention, then restarts the
    AVD agent services, removes the NSG deny rule created by the network break,
    deletes C:\bloat.bin, and deletes the simulated FSLogix lock file.

.PARAMETER ResourceGroupName
    Resource group containing the AVD resources.

.EXAMPLE
    .\fix-avd.ps1 -ResourceGroupName rg-srelab-eastus2
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'
$ruleName = 'deny-avd-sta-443'

function Get-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $raw = & az @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw $raw.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Get-AvdSessionHosts {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName
    )

    $vms = Get-AzJson -Arguments @('vm', 'list', '--resource-group', $ResourceGroupName, '--output', 'json')
    return @($vms | Where-Object {
            $isTagged = $null -ne $_.tags -and $_.tags.PSObject.Properties.Name -contains 'avdRole' -and $_.tags.avdRole -eq 'session-host'
            $isNamed = $_.name -like 'vm-avd-*'
            $isTagged -or $isNamed
        } | Sort-Object -Property name)
}

function Invoke-RunCommand {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$VmName,

        [Parameter(Mandatory)]
        [string]$Script
    )

    az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --command-id RunPowerShellScript `
        --scripts $Script `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Run command failed on $VmName."
    }
}

$sessionHosts = Get-AvdSessionHosts -ResourceGroupName $ResourceGroupName
if ($sessionHosts.Count -eq 0) {
    Write-Host "⚠️ No AVD session hosts were discovered in '$ResourceGroupName'." -ForegroundColor Yellow
}
else {
    $repairScript = @'
$serviceNames = @('RDAgentBootLoader', 'Remote Desktop Agent Loader')
foreach ($serviceName in $serviceNames) {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        Set-Service -Name $serviceName -StartupType Automatic -ErrorAction SilentlyContinue
        if ($service.Status -ne 'Running') {
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        }
    }
}
if (Test-Path 'C:\bloat.bin') {
    Remove-Item 'C:\bloat.bin' -Force
}
$lockFiles = @(
    'C:\FSLogix\Profiles\demo-user\Profile_demo.vhdx.lock'
)
foreach ($lockFile in $lockFiles) {
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
}
Get-Service -Name $serviceNames -ErrorAction SilentlyContinue | Select-Object Name, Status
'@

    foreach ($sessionHost in $sessionHosts) {
        if ($PSCmdlet.ShouldProcess($sessionHost.name, 'Restart AVD services and remove demo artifacts')) {
            Invoke-RunCommand -ResourceGroupName $ResourceGroupName -VmName $sessionHost.name -Script $repairScript
            Write-Host "✅ Repaired $($sessionHost.name)" -ForegroundColor Green
        }
    }
}

$nsgs = Get-AzJson -Arguments @('network', 'nsg', 'list', '--resource-group', $ResourceGroupName, '--output', 'json')
$matchedNsgs = @($nsgs | Where-Object {
        $ruleNames = @($_.securityRules | ForEach-Object { $_.name })
        $ruleNames -contains $ruleName
    })

if ($matchedNsgs.Count -eq 0) {
    Write-Host "ℹ️ No NSG deny rule named '$ruleName' was found." -ForegroundColor Yellow
}
else {
    foreach ($nsg in $matchedNsgs) {
        if ($PSCmdlet.ShouldProcess($nsg.name, 'Remove demo deny rule')) {
            az network nsg rule delete `
                --resource-group $ResourceGroupName `
                --nsg-name $nsg.name `
                --name $ruleName `
                --only-show-errors `
                --output none

            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove '$ruleName' from NSG '$($nsg.name)'."
            }

            Write-Host "✅ Removed $ruleName from $($nsg.name)" -ForegroundColor Green
        }
    }
}

Write-Host "✅ AVD demo remediation complete." -ForegroundColor Green
