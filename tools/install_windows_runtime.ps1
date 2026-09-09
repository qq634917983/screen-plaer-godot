param([Parameter(Mandatory = $true)][string]$SourceRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = (Resolve-Path -LiteralPath $SourceRoot).Path
$manifest = Get-Content "$PSScriptRoot/windows-runtime.lock.json" -Raw | ConvertFrom-Json
# Validate the entire source before changing any installed files.
foreach ($file in $manifest.files) {
    $source = Join-Path $sourcePath $file.path
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing runtime: $source" }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $file.sha256) {
        throw "Runtime SHA-256 mismatch: $source. Use the version matching windows-runtime.lock.json."
    }
}
foreach ($file in $manifest.files) {
    $target = Join-Path $projectRoot $file.path
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $file.sha256) { continue }
        throw "Existing runtime differs: $target. Back it up before replacing it."
    }
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourcePath $file.path) -Destination $target
}
& "$PSScriptRoot/check_windows_runtime.ps1"
