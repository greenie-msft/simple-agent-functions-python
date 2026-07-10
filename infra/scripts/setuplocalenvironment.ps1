#!/usr/bin/env pwsh
# azd postprovision hook entry point. Runs after `azd provision` / `azd up` to
# prepare the local development environment. Add more setup steps here as needed.

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'createlocalsettings.ps1')
