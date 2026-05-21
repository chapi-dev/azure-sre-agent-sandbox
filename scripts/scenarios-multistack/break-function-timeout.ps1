<#
.SYNOPSIS
    Deploys a slow Azure Function that times out on the Consumption plan.

.DESCRIPTION
    Publishes an inline HTTP-triggered function that waits 250 seconds before
    responding, exceeding the default HTTP execution window for a Consumption
    plan and creating an end-to-end timeout scenario.

.PARAMETER ResourceGroupName
    Resource group containing the Function App.

.PARAMETER FunctionAppName
    Name of the Function App to update.

.EXAMPLE
    .\break-function-timeout.ps1 -ResourceGroupName rg-srelab-eastus2 -FunctionAppName func-srelab-abc123
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$FunctionAppName
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$AsJson
    )

    $output = & az @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
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
  "name": "multistack-function-timeout",
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

    $zipPath = Join-Path $PSScriptRoot 'function-timeout-package.zip'
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $RootPath '*') -DestinationPath $zipPath -Force
    return $zipPath
}

$stagingRoot = Join-Path $PSScriptRoot '.generated-function-timeout'
$zipPath = $null

try {
    $zipPath = New-FunctionScenarioPackage -RootPath $stagingRoot -JavaScriptBody @"
module.exports = async function (context, req) {
    context.log('Starting slow timeout scenario function.');
    await new Promise((resolve) => setTimeout(resolve, 250000));

    context.res = {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
        body: {
            scenario: 'function-timeout',
            waitedMs: 250000,
            completedAt: new Date().toISOString()
        }
    };
};
"@

    if ($PSCmdlet.ShouldProcess($FunctionAppName, 'Deploy slow timeout function package')) {
        Invoke-AzCli -Arguments @(
            'functionapp', 'deployment', 'source', 'config-zip',
            '--resource-group', $ResourceGroupName,
            '--name', $FunctionAppName,
            '--src', $zipPath,
            '--output', 'json'
        ) -AsJson | Out-Null
    }

    $defaultHostName = Invoke-AzCli -Arguments @(
        'functionapp', 'show',
        '--resource-group', $ResourceGroupName,
        '--name', $FunctionAppName,
        '--query', 'defaultHostName',
        '--output', 'tsv'
    )

    Write-Host "✅ Slow timeout function deployed." -ForegroundColor Green
    Write-Host "   Function App : $FunctionAppName" -ForegroundColor Gray
    Write-Host "   Endpoint     : https://$defaultHostName/api/slow-timeout" -ForegroundColor Yellow
    Write-Host "   Expected symptom: HTTP requests hang until the Consumption timeout window is exceeded." -ForegroundColor Gray
}
finally {
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force
    }

    if ($zipPath -and (Test-Path $zipPath)) {
        Remove-Item -Path $zipPath -Force
    }
}
