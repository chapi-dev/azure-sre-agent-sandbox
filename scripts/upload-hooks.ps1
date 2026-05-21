<#
.SYNOPSIS
    Uploads Module D hook definitions to the Azure SRE Agent dataplane API.

.DESCRIPTION
    Discovers the SRE Agent in the supplied resource group, acquires a bearer token,
    and posts every hook YAML in sre-config\hooks to the extendedAgent hooks endpoint.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $raw = Invoke-Expression $Command 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: $Command`n$raw"
    }

    $jsonObjectStart = $raw.IndexOf('{')
    $jsonArrayStart = $raw.IndexOf('[')
    if ($jsonObjectStart -ge 0 -and $jsonArrayStart -ge 0) {
        $jsonStart = [Math]::Min($jsonObjectStart, $jsonArrayStart)
    }
    elseif ($jsonObjectStart -ge 0) {
        $jsonStart = $jsonObjectStart
    }
    elseif ($jsonArrayStart -ge 0) {
        $jsonStart = $jsonArrayStart
    }
    else {
        $jsonStart = -1
    }

    $jsonContent = if ($jsonStart -ge 0) { $raw.Substring($jsonStart) } else { $raw }
    return $jsonContent | ConvertFrom-Json
}

function Get-SreAgentContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName
    )

    Write-Host "🔍 Discovering SRE Agent in $ResourceGroupName..." -ForegroundColor Yellow
    $agents = @(Invoke-AzCliJson -Command "az resource list --resource-group `"$ResourceGroupName`" --resource-type `"Microsoft.App/agents`" --output json")
    if ($agents.Count -eq 0) {
        throw "No SRE Agent found in $ResourceGroupName."
    }

    $agent = $agents[0]
    $agentDetail = Invoke-AzCliJson -Command "az resource show --ids `"$($agent.id)`" --api-version 2025-05-01-preview --output json"
    if ([string]::IsNullOrWhiteSpace($agentDetail.properties.agentEndpoint)) {
        throw 'The SRE Agent endpoint is not available yet.'
    }

    Write-Host "  ✅ Found agent endpoint: $($agentDetail.properties.agentEndpoint)" -ForegroundColor Green
    return [pscustomobject]@{
        Name     = $agent.name
        Endpoint = $agentDetail.properties.agentEndpoint
    }
}

function Get-SreAgentToken {
    $token = az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw 'Failed to acquire a bearer token for the SRE Agent dataplane API.'
    }

    return $token.Trim()
}

function Invoke-YamlPost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$YamlContent
    )

    $client = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)

    try {
        $content = [System.Net.Http.StringContent]::new($YamlContent, [System.Text.Encoding]::UTF8, 'application/yaml')
        $response = $client.PostAsync($Url, $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body       = $body
        }
    }
    finally {
        $client.Dispose()
    }
}

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                          Upload Module D Hooks                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$agentContext = Get-SreAgentContext -ResourceGroupName $ResourceGroupName
$token = Get-SreAgentToken
$hooksDir = Join-Path $PSScriptRoot '..\sre-config\hooks'
$uploadUrl = "$($agentContext.Endpoint)/api/v2/extendedAgent/hooks"
$hookFiles = Get-ChildItem -Path $hooksDir -Filter '*.yaml' | Sort-Object Name

if ($hookFiles.Count -eq 0) {
    throw "No hook YAML files were found in $hooksDir."
}

$successCount = 0
foreach ($hookFile in $hookFiles) {
    if (-not $PSCmdlet.ShouldProcess($hookFile.Name, 'Upload hook definition')) {
        continue
    }

    Write-Host "🪝 Uploading $($hookFile.Name)..." -ForegroundColor Yellow
    $yamlContent = Get-Content -Path $hookFile.FullName -Raw
    $response = Invoke-YamlPost -Url $uploadUrl -Token $token -YamlContent $yamlContent

    if ($response.StatusCode -in 200, 201, 202, 204) {
        $successCount++
        Write-Host "  ✅ Uploaded $($hookFile.BaseName)" -ForegroundColor Green
    }
    else {
        Write-Warning "Upload failed for $($hookFile.Name) (HTTP $($response.StatusCode)). $($response.Body)"
    }
}

Write-Host "`n📊 Uploaded $successCount of $($hookFiles.Count) hook definition(s)." -ForegroundColor Cyan