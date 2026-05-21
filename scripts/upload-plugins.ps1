<#
.SYNOPSIS
    Uploads Module D plugin definitions to the Azure SRE Agent dataplane API.

.DESCRIPTION
    Discovers the SRE Agent in the supplied resource group, replaces the mock CMDB
    base URL placeholder, injects the Function key header value for the CMDB plugin,
    and posts every plugin YAML in sre-config\plugins to the dataplane plugins endpoint.

.PARAMETER ResourceGroupName
    Name of the resource group containing the SRE Agent.

.PARAMETER MockCmdbUrl
    Base URL for the mock CMDB Function App, typically https://<function-app>.azurewebsites.net/api.

.PARAMETER MockCmdbKey
    Function key used for the mock CMDB plugin's x-functions-key header.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$MockCmdbUrl,

    [Parameter(Mandatory)]
    [string]$MockCmdbKey
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

function ConvertTo-YamlSingleQuotedScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-PluginYamlContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PluginPath,

        [Parameter(Mandatory)]
        [string]$MockCmdbUrl,

        [Parameter(Mandatory)]
        [string]$MockCmdbKey
    )

    $content = Get-Content -Path $PluginPath -Raw
    $normalizedUrl = $MockCmdbUrl.TrimEnd('/')
    $content = $content.Replace('MOCK_CMDB_URL_PLACEHOLDER', $normalizedUrl)

    if ((Split-Path -Path $PluginPath -Leaf) -eq 'cmdb-http-plugin.yaml') {
        $quotedKey = ConvertTo-YamlSingleQuotedScalar -Value $MockCmdbKey
        if ($content -notmatch '(?m)^\s+value:\s+') {
            $content = $content -replace '(?m)^(\s+name:\s+x-functions-key\s*)$', "`$1`r`n    value: $quotedKey"
        }
    }

    return $content
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
║                         Upload Module D Plugins                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$agentContext = Get-SreAgentContext -ResourceGroupName $ResourceGroupName
$token = Get-SreAgentToken
$pluginsDir = Join-Path $PSScriptRoot '..\sre-config\plugins'
$uploadUrl = "$($agentContext.Endpoint)/api/v2/extendedAgent/plugins"
$pluginFiles = Get-ChildItem -Path $pluginsDir -Filter '*.yaml' | Sort-Object Name

if ($pluginFiles.Count -eq 0) {
    throw "No plugin YAML files were found in $pluginsDir."
}

$successCount = 0
foreach ($pluginFile in $pluginFiles) {
    if (-not $PSCmdlet.ShouldProcess($pluginFile.Name, 'Upload plugin definition')) {
        continue
    }

    Write-Host "🔌 Uploading $($pluginFile.Name)..." -ForegroundColor Yellow
    $yamlContent = Get-PluginYamlContent -PluginPath $pluginFile.FullName -MockCmdbUrl $MockCmdbUrl -MockCmdbKey $MockCmdbKey
    $response = Invoke-YamlPost -Url $uploadUrl -Token $token -YamlContent $yamlContent

    if ($response.StatusCode -in 200, 201, 202, 204) {
        $successCount++
        Write-Host "  ✅ Uploaded $($pluginFile.BaseName)" -ForegroundColor Green
    }
    else {
        Write-Warning "Upload failed for $($pluginFile.Name) (HTTP $($response.StatusCode)). $($response.Body)"
    }
}

Write-Host "`n📊 Uploaded $successCount of $($pluginFiles.Count) plugin definition(s)." -ForegroundColor Cyan