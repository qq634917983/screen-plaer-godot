# Restore only the known Windows DLLs; never overwrite the cross-platform manifest.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archivePath = Join-Path $projectRoot 'bin/win-bin.zip'
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Missing Windows runtime archive: $archivePath"
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$names = @('libgodot_mpv.windows.template_release.x86_64.dll',
    'libmpv-2.dll', 'libEGL.dll', 'libGLESv2.dll', 'zlib1.dll')
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($name in $names) {
        if (-not $archive.GetEntry("bin/$name")) {
            throw "Runtime archive is missing bin/$name"
        }
    }
    foreach ($name in $names) {
        $entry = $archive.GetEntry("bin/$name")
        $destination = Join-Path $projectRoot "bin/$name"
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
        Write-Host "Restored bin/$name"
    }
} finally {
    $archive.Dispose()
}
