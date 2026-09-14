param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$TemplateArchive = $env:GODOT_EXPORT_TEMPLATES,
    [string]$InnoCompiler,
    [switch]$SkipReleaseBuild
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

if (-not $SkipReleaseBuild) {
    $releaseArgs = @{}
    if ($Godot) { $releaseArgs.Godot = $Godot }
    if ($TemplateArchive) { $releaseArgs.TemplateArchive = $TemplateArchive }
    & "$PSScriptRoot/build_windows_release.ps1" @releaseArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$releaseDir = Join-Path $projectRoot 'dist/ScreenPlayer-Windows-x86_64'
$required = @('ScreenPlayer.exe', 'libgodot_mpv.windows.template_release.x86_64.dll',
    'libmpv-2.dll', 'libgdcef.dll', 'libcef.dll', 'gdCefRenderProcess.exe',
    'locales/zh-CN.pak', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$missing = @($required | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $releaseDir $_) -PathType Leaf)
})
if ($missing.Count) {
    throw "Release directory is incomplete. Missing:`n$($missing -join "`n")"
}

if (-not $InnoCompiler) {
    $candidates = @(
        (Join-Path $projectRoot '.build/InnoSetup/ISCC.exe'),
        'C:/Program Files/Inno Setup 7/ISCC.exe',
        'C:/Program Files (x86)/Inno Setup 6/ISCC.exe',
        'C:/Program Files/Inno Setup 6/ISCC.exe'
    )
    $InnoCompiler = $candidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
}
if (-not $InnoCompiler) {
    throw 'Inno Setup ISCC.exe was not found. Install Inno Setup 7 or pass -InnoCompiler.'
}

$projectText = Get-Content (Join-Path $projectRoot 'project.godot') -Raw
$versionMatch = [regex]::Match($projectText, '(?m)^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$')
if (-not $versionMatch.Success) { throw 'project.godot config/version must use x.y.z.' }
$version = $versionMatch.Groups[1].Value
$outputDir = Join-Path $projectRoot 'dist'
$scriptPath = Join-Path $projectRoot 'installer/ScreenPlayer.iss'

& $InnoCompiler "/DAppVersion=$version" "/DSourceDir=$releaseDir" `
    "/DOutputDir=$outputDir" $scriptPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$installerPath = Join-Path $outputDir "ScreenPlayer-Setup-$version.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer was not created: $installerPath"
}
$installer = Get-Item -LiteralPath $installerPath
$hash = Get-FileHash -LiteralPath $installerPath -Algorithm SHA256
Write-Host "Installer: $($installer.FullName)"
Write-Host ("Size:      {0:N2} MB" -f ($installer.Length / 1MB))
Write-Host "SHA256:    $($hash.Hash)"
