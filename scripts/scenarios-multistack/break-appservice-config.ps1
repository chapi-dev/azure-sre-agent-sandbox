<#
.SYNOPSIS
    Breaks the App Service configuration for the multi-stack demo.

.DESCRIPTION
    Sets the Cosmos__Endpoint app setting to an invalid value so the front-end
    web app fails when it tries to reach Cosmos DB.

.PARAMETER ResourceGroupName
    Resource group containing the App Service resource.

.PARAMETER AppServiceName
    Name of the App Service web app to update.

.EXAMPLE
    .\break-appservice-config.ps1 -ResourceGroupName rg-srelab-eastus2 -AppServiceName app-srelab
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$AppServiceName
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

$brokenEndpoint = 'https://invalid.documents.azure.com'

if ($PSCmdlet.ShouldProcess($AppServiceName, 'Set Cosmos__Endpoint to an invalid endpoint')) {
    Invoke-AzCli -Arguments @(
        'webapp', 'config', 'appsettings', 'set',
        '--resource-group', $ResourceGroupName,
        '--name', $AppServiceName,
        '--settings', "Cosmos__Endpoint=$brokenEndpoint",
        '--output', 'json'
    ) -AsJson | Out-Null
}

$currentValue = Invoke-AzCli -Arguments @(
    'webapp', 'config', 'appsettings', 'list',
    '--resource-group', $ResourceGroupName,
    '--name', $AppServiceName,
    '--query', "[?name=='Cosmos__Endpoint'].value | [0]",
    '--output', 'tsv'
)

Write-Host "✅ App Service setting updated." -ForegroundColor Green
Write-Host "   App Service : $AppServiceName" -ForegroundColor Gray
Write-Host "   Cosmos__Endpoint = $currentValue" -ForegroundColor Yellow
Write-Host "   Expected symptom: front-end failures before or during Cosmos calls." -ForegroundColor Gray
