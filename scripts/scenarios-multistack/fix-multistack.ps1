<#
.SYNOPSIS
    Restores the Movistar BSS multi-stack demo back to a healthy baseline.

.DESCRIPTION
    Reverts the demo break scenarios by restoring Cosmos DB throughput, fixing the
    App Service Cosmos endpoint setting, redeploying a fast Function payload, and
    stopping any SQL DTU load workers previously started by break-sql-dtu.ps1.
    Resource names can be supplied explicitly or auto-discovered from tags and
    naming conventions inside the specified resource group.

.PARAMETER ResourceGroupName
    Resource group containing the multi-stack demo resources.

.PARAMETER CosmosAccountName
    Optional explicit Cosmos DB account name.

.PARAMETER AppServiceName
    Optional explicit App Service name.

.PARAMETER FunctionAppName
    Optional explicit Function App name.

.PARAMETER SqlServerName
    Optional explicit Azure SQL logical server name.

.EXAMPLE
    .\fix-multistack.ps1 -ResourceGroupName rg-srelab-eastus2
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$CosmosAccountName,

    [Parameter()]
    [string]$AppServiceName,

    [Parameter()]
    [string]$FunctionAppName,

    [Parameter()]
    [string]$SqlServerName
)

$ErrorActionPreference = 'Stop'

$databaseName = 'movistar-bss-db'
$containerName = 'plans-catalog'
$baselineThroughput = 400
$stateRoot = Join-Path $PSScriptRoot '.state'
$stateFile = Join-Path $stateRoot 'sql-dtu-processes.json'
$sqlFile = Join-Path $stateRoot 'sql-dtu-load.sql'
$resourceInventory = $null

function Invoke-AzCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$AsJson,

        [Parameter()]
        [switch]$AllowFailure
    )

    $output = & az @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')`n$output"
    }

    if ($AsJson) {
        if ([string]::IsNullOrWhiteSpace($output)) {
            return $null
        }

        return $output | ConvertFrom-Json
    }

    return $output.Trim()
}

function Get-ResourceInventory {
    [CmdletBinding()]
    param()

    if ($null -eq $resourceInventory) {
        $resourceInventory = Invoke-AzCli -Arguments @(
            'resource', 'list',
            '--resource-group', $ResourceGroupName,
            '--output', 'json'
        ) -AsJson
    }

    return @($resourceInventory)
}

function Resolve-ResourceName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ExplicitName,

        [Parameter(Mandatory)]
        [string]$ResourceType,

        [Parameter(Mandatory)]
        [string]$NamePrefix
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitName)) {
        return $ExplicitName
    }

    $inventory = Get-ResourceInventory
    $match = @(
        $inventory |
            Where-Object {
                $_.type -eq $ResourceType -and
                $_.name -like "$NamePrefix*" -and
                $_.tags.workload -eq 'sre-agent-demo'
            }
    ) | Select-Object -First 1

    if ($null -eq $match) {
        $match = @(
            $inventory |
                Where-Object {
                    $_.type -eq $ResourceType -and
                    $_.name -like "$NamePrefix*"
                }
        ) | Select-Object -First 1
    }

    if ($null -eq $match) {
        return $null
    }

    return $match.name
}

function New-FunctionScenarioPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string]$JavaScriptBody
    )

    if (Test-Path $RootPath) {
        Remove-Item -Path $RootPath -Recurse -Force
    }

    $functionPath = Join-Path $RootPath 'slowTimeout'
    New-Item -ItemType Directory -Path $functionPath -Force | Out-Null

    Set-Content -Path (Join-Path $RootPath 'host.json') -Encoding UTF8 -Value @"
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
"@

    Set-Content -Path (Join-Path $RootPath 'package.json') -Encoding UTF8 -Value @"
{
  "name": "multistack-function-fast",
  "version": "1.0.0",
  "private": true
}
"@

    Set-Content -Path (Join-Path $functionPath 'function.json') -Encoding UTF8 -Value @"
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get", "post"],
      "route": "slow-timeout"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
"@

    Set-Content -Path (Join-Path $functionPath 'index.js') -Encoding UTF8 -Value $JavaScriptBody

    $zipPath = Join-Path $PSScriptRoot 'function-fast-package.zip'
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $RootPath '*') -DestinationPath $zipPath -Force
    return $zipPath
}

function Publish-FastFunctionPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetFunctionAppName
    )

    $stagingRoot = Join-Path $PSScriptRoot '.generated-function-fast'
    $zipPath = $null

    try {
        $zipPath = New-FunctionScenarioPackage -RootPath $stagingRoot -JavaScriptBody @"
module.exports = async function (context, req) {
    context.res = {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
            scenario: 'recovered',
            status: 'healthy',
            completedAt: new Date().toISOString()
        }
    };
};
"@

        if ($PSCmdlet.ShouldProcess($TargetFunctionAppName, 'Deploy healthy function package')) {
            Invoke-AzCli -Arguments @(
                'functionapp', 'deployment', 'source', 'config-zip',
                '--resource-group', $ResourceGroupName,
                '--name', $TargetFunctionAppName,
                '--src', $zipPath,
                '--output', 'json'
            ) -AsJson | Out-Null
        }
    }
    finally {
        if (Test-Path $stagingRoot) {
            Remove-Item -Path $stagingRoot -Recurse -Force
        }

        if ($zipPath -and (Test-Path $zipPath)) {
            Remove-Item -Path $zipPath -Force
        }
    }
}

function Stop-SqlScenarioProcesses {
    [CmdletBinding()]
    param()

    $stoppedPids = [System.Collections.Generic.List[int]]::new()
    $stateRecords = @()

    if (Test-Path $stateFile) {
        $raw = Get-Content -Path $stateFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $stateRecords = @($raw | ConvertFrom-Json)
        }
    }

    foreach ($record in $stateRecords) {
        $process = Get-Process -Id $record.pid -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            if ($PSCmdlet.ShouldProcess("PID $($record.pid)", 'Stop SQL DTU load worker')) {
                Stop-Process -Id $record.pid -Force
                [void]$stoppedPids.Add([int]$record.pid)
            }
        }
    }

    $targetSqlServerName = $SqlServerName
    if ([string]::IsNullOrWhiteSpace($targetSqlServerName) -and $stateRecords.Count -gt 0) {
        $targetSqlServerName = $stateRecords[0].serverName
    }

    $helperFirewallRule = if ($stateRecords.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($stateRecords[0].firewallRuleName)) {
        $stateRecords[0].firewallRuleName
    }
    else {
        'AllowMultistackScenarioClient'
    }

    if (-not [string]::IsNullOrWhiteSpace($targetSqlServerName) -and $PSCmdlet.ShouldProcess($targetSqlServerName, "Delete helper firewall rule $helperFirewallRule")) {
        Invoke-AzCli -Arguments @(
            'sql', 'server', 'firewall-rule', 'delete',
            '--resource-group', $ResourceGroupName,
            '--server', $targetSqlServerName,
            '--name', $helperFirewallRule
        ) -AllowFailure | Out-Null
    }

    if (Test-Path $stateFile) {
        Remove-Item -Path $stateFile -Force
    }

    if (Test-Path $sqlFile) {
        Remove-Item -Path $sqlFile -Force
    }

    if (Test-Path $stateRoot) {
        $remaining = Get-ChildItem -Path $stateRoot -Force | Select-Object -First 1
        if ($null -eq $remaining) {
            Remove-Item -Path $stateRoot -Force
        }
    }

    return @($stoppedPids)
}

$resolvedCosmosAccountName = Resolve-ResourceName -ExplicitName $CosmosAccountName -ResourceType 'Microsoft.DocumentDB/databaseAccounts' -NamePrefix 'cosmos-'
$resolvedAppServiceName = Resolve-ResourceName -ExplicitName $AppServiceName -ResourceType 'Microsoft.Web/sites' -NamePrefix 'app-'
$resolvedFunctionAppName = Resolve-ResourceName -ExplicitName $FunctionAppName -ResourceType 'Microsoft.Web/sites' -NamePrefix 'func-'

$cosmosEndpoint = $null
if (-not [string]::IsNullOrWhiteSpace($resolvedCosmosAccountName)) {
    if ($PSCmdlet.ShouldProcess("$resolvedCosmosAccountName/$databaseName/$containerName", "Restore throughput to $baselineThroughput RU/s")) {
        Invoke-AzCli -Arguments @(
            'cosmosdb', 'sql', 'container', 'throughput', 'update',
            '--resource-group', $ResourceGroupName,
            '--account-name', $resolvedCosmosAccountName,
            '--database-name', $databaseName,
            '--name', $containerName,
            '--throughput', $baselineThroughput.ToString(),
            '--output', 'json'
        ) -AsJson | Out-Null
    }

    $cosmosEndpoint = Invoke-AzCli -Arguments @(
        'cosmosdb', 'show',
        '--resource-group', $ResourceGroupName,
        '--name', $resolvedCosmosAccountName,
        '--query', 'documentEndpoint',
        '--output', 'tsv'
    )
}
else {
    Write-Warning 'Cosmos DB account could not be resolved. Skipping throughput restore.'
}

if (-not [string]::IsNullOrWhiteSpace($resolvedAppServiceName) -and -not [string]::IsNullOrWhiteSpace($cosmosEndpoint)) {
    if ($PSCmdlet.ShouldProcess($resolvedAppServiceName, 'Restore Cosmos__Endpoint app setting')) {
        Invoke-AzCli -Arguments @(
            'webapp', 'config', 'appsettings', 'set',
            '--resource-group', $ResourceGroupName,
            '--name', $resolvedAppServiceName,
            '--settings', "Cosmos__Endpoint=$cosmosEndpoint",
            '--output', 'json'
        ) -AsJson | Out-Null
    }
}
elseif ([string]::IsNullOrWhiteSpace($resolvedAppServiceName)) {
    Write-Warning 'App Service name could not be resolved. Skipping app setting repair.'
}

if (-not [string]::IsNullOrWhiteSpace($resolvedFunctionAppName)) {
    Publish-FastFunctionPackage -TargetFunctionAppName $resolvedFunctionAppName
}
else {
    Write-Warning 'Function App name could not be resolved. Skipping function package restore.'
}

$stoppedSqlPids = Stop-SqlScenarioProcesses

Write-Host "✅ Multi-stack recovery actions completed." -ForegroundColor Green
if (-not [string]::IsNullOrWhiteSpace($resolvedCosmosAccountName)) {
    Write-Host "   Cosmos DB   : restored $databaseName/$containerName to $baselineThroughput RU/s" -ForegroundColor Gray
}
if (-not [string]::IsNullOrWhiteSpace($resolvedAppServiceName) -and -not [string]::IsNullOrWhiteSpace($cosmosEndpoint)) {
    Write-Host "   App Service : restored Cosmos__Endpoint on $resolvedAppServiceName" -ForegroundColor Gray
}
if (-not [string]::IsNullOrWhiteSpace($resolvedFunctionAppName)) {
    Write-Host "   Function    : deployed healthy payload to $resolvedFunctionAppName" -ForegroundColor Gray
}
if ($stoppedSqlPids.Count -gt 0) {
    Write-Host "   SQL load     : stopped PIDs $($stoppedSqlPids -join ', ')" -ForegroundColor Gray
}
else {
    Write-Host "   SQL load     : no tracked query bomb processes were running" -ForegroundColor Gray
}
