#!/usr/bin/env pwsh
# Writes src/local.settings.json from the current azd environment so the
# function app can run locally with `uv run func start`. An existing file is
# left untouched so your local edits are never overwritten.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$settingsFile = Join-Path $repoRoot 'src' 'local.settings.json'

if (Test-Path $settingsFile) {
    Write-Host "$settingsFile already exists; leaving it unchanged."
    exit 0
}

if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
    Write-Warning "azd not found; skipping $settingsFile generation."
    exit 0
}

$values = @{}
foreach ($line in (azd env get-values)) {
    if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
        $values[$Matches.k] = $Matches.v.Trim('"')
    }
}

function Get-OrDefault([string]$key, [string]$default) {
    if ($values.ContainsKey($key) -and $values[$key]) { return $values[$key] }
    return $default
}

$settings = [ordered]@{
    IsEncrypted = $false
    Values      = [ordered]@{
        FUNCTIONS_WORKER_RUNTIME        = 'python'
        AzureWebJobsStorage             = 'UseDevelopmentStorage=true'
        AZURE_FUNCTIONS_AGENTS_PROVIDER = 'foundry'
        FOUNDRY_PROJECT_ENDPOINT        = (Get-OrDefault 'FOUNDRY_PROJECT_ENDPOINT' '')
        FOUNDRY_MODEL                   = (Get-OrDefault 'FOUNDRY_MODEL' 'gpt-5-mini')
        GITHUB_REPOSITORY               = (Get-OrDefault 'GITHUB_REPOSITORY' 'Azure/azure-functions-host')
    }
}

$settings | ConvertTo-Json | Set-Content -Path $settingsFile -Encoding utf8
Write-Host "Wrote $settingsFile."
