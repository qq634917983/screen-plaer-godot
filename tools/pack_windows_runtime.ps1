param([string]$Destination = "$PSScriptRoot/../dist/screenplayer-runtime-windows-x86_64-2026-09-09.zip")
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/check_windows_runtime.ps1"
$projectRoot = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content "$PSScriptRoot/windows-runtime.lock.json" -Raw | ConvertFrom-Json
$archivePath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $archivePath) { throw "Archive already exists: $archivePath" }
New-Item -ItemType Directory -Path (Split-Path $archivePath -Parent) -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $manifest.files) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,
            (Join-Path $projectRoot $file.path), $file.path,
            [IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
} finally { $archive.Dispose() }
Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
