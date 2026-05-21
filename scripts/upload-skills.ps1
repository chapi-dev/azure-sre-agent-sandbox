<#
.SYNOPSIS
    Uploads Module D skill definitions to the Azure SRE Agent dataplane API.

.DESCRIPTION
    Discovers the SRE Agent in the supplied resource group, acquires a bearer token
    for the dataplane API, and uploads every skill YAML in sre-config\skills together
    with its Python entrypoint and requirements.txt (when present) as multipart form data.

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

function Get-EntrypointPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$YamlPath
    )

    $yamlContent = Get-Content -Path $YamlPath -Raw
    if ($yamlContent -match '(?m)^\s*entrypoint:\s*([^:]+):') {
        return Join-Path (Split-Path -Path $YamlPath -Parent) $Matches[1].Trim()
    }

    return [System.IO.Path]::ChangeExtension($YamlPath, '.py')
}

function Invoke-SkillUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter(Mandatory)]
        [string]$YamlPath,

        [Parameter(Mandatory)]
        [string]$PythonPath,

        [string]$RequirementsPath
    )

    $client = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
    $multipart = [System.Net.Http.MultipartFormDataContent]::new()

    try {
        $files = @(
            @{ Path = $YamlPath; ContentType = 'application/yaml' }
            @{ Path = $PythonPath; ContentType = 'text/x-python' }
        )

        if ($RequirementsPath -and (Test-Path $RequirementsPath)) {
            $files += @{ Path = $RequirementsPath; ContentType = 'text/plain' }
        }

        foreach ($file in $files) {
            $content = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($file.Path))
            $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($file.ContentType)
            $multipart.Add($content, 'files', [System.IO.Path]::GetFileName($file.Path))
        }

        $response = $client.PostAsync($Url, $multipart).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body       = $body
        }
    }
    finally {
        $multipart.Dispose()
        $client.Dispose()
    }
}

Write-Host @"

╔══════════════════════════════════════════════════════════════════════════════╗
║                         Upload Module D Skills                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$agentContext = Get-SreAgentContext -ResourceGroupName $ResourceGroupName
$token = Get-SreAgentToken
$skillsDir = Join-Path $PSScriptRoot '..\sre-config\skills'
$requirementsPath = Join-Path $skillsDir 'requirements.txt'
$uploadUrl = "$($agentContext.Endpoint)/api/v2/extendedAgent/skills"
$skillFiles = Get-ChildItem -Path $skillsDir -Filter '*.yaml' | Sort-Object Name

if ($skillFiles.Count -eq 0) {
    throw "No skill YAML files were found in $skillsDir."
}

$successCount = 0
foreach ($skillFile in $skillFiles) {
    $pythonPath = Get-EntrypointPath -YamlPath $skillFile.FullName
    if (-not (Test-Path $pythonPath)) {
        Write-Warning "Skipping $($skillFile.Name) because the Python entrypoint was not found: $pythonPath"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($skillFile.Name, 'Upload skill bundle')) {
        continue
    }

    Write-Host "📦 Uploading $($skillFile.Name)..." -ForegroundColor Yellow
    $response = Invoke-SkillUpload -Url $uploadUrl -Token $token -YamlPath $skillFile.FullName -PythonPath $pythonPath -RequirementsPath $requirementsPath

    if ($response.StatusCode -in 200, 201, 202, 204) {
        $successCount++
        Write-Host "  ✅ Uploaded $($skillFile.BaseName)" -ForegroundColor Green
    }
    else {
        Write-Warning "Upload failed for $($skillFile.Name) (HTTP $($response.StatusCode)). $($response.Body)"
    }
}

Write-Host "`n📊 Uploaded $successCount of $($skillFiles.Count) skill bundle(s)." -ForegroundColor Cyan