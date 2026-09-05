#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the Conftest naming-convention check against the naming-check Terraform example.
.DESCRIPTION
    Mirrors the "naming-check" job in .github/workflows/terraform.yml for local use:
    plans infra/terraform/examples/naming-check, converts the plan to JSON, and
    runs conftest against infra/policy. Downloads conftest into .tools/ if it
    isn't already on PATH.
.PARAMETER ConftestVersion
    conftest release to download if it isn't already installed. Defaults to the
    version pinned in .github/workflows/terraform.yml.
#>

[CmdletBinding()]
param(
    [string]$ConftestVersion = "0.55.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).ProviderPath
$policyDir = Join-Path $repoRoot "infra\policy"
$exampleDir = Join-Path $repoRoot "infra\terraform\examples\naming-check"
$toolsDir = Join-Path $repoRoot ".tools"
$conftestExe = Join-Path $toolsDir "conftest.exe"

function Get-ConftestPath {
    $onPath = Get-Command conftest -ErrorAction SilentlyContinue
    if ($onPath) {
        return $onPath.Source
    }
    if (Test-Path $conftestExe) {
        return $conftestExe
    }

    Write-Host "conftest not found on PATH; downloading v$ConftestVersion into $toolsDir..."
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
    $zipPath = Join-Path $toolsDir "conftest.zip"
    $url = "https://github.com/open-policy-agent/conftest/releases/download/v$ConftestVersion/conftest_${ConftestVersion}_Windows_x86_64.zip"
    Invoke-WebRequest -Uri $url -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
    Remove-Item $zipPath -ErrorAction SilentlyContinue

    return $conftestExe
}

$conftest = Get-ConftestPath

Push-Location $exampleDir
try {
    terraform init -backend=false -input=false | Out-Null
    # Space-separated -out avoids a Windows PowerShell native-arg-passing bug
    # that mis-splits "-out=<file>.<ext>" (equals sign + dotted filename).
    terraform plan -out tfplan.binary -input=false | Out-Null
    # Out-File -Encoding utf8 adds a BOM on Windows PowerShell 5.1, which the
    # Go JSON parser conftest uses rejects, so write UTF-8 without BOM directly.
    $planJsonText = terraform show -json tfplan.binary | Out-String
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $exampleDir "plan.json"), $planJsonText.Trim(), $utf8NoBom)
}
finally {
    Pop-Location
}

$planJson = Join-Path $exampleDir "plan.json"
& $conftest test --policy $policyDir $planJson
exit $LASTEXITCODE
