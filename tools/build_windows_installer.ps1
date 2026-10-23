param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$TemplateArchive = $env:GODOT_EXPORT_TEMPLATES,
    [string]$VCRuntimeDirectory,
    [string]$InnoCompiler,
    [switch]$SkipReleaseBuild,
    [switch]$SkipInstallerCompile,
    [switch]$IncludeTempWorkaround
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if ($SkipInstallerCompile -and -not $SkipReleaseBuild) {
    throw '-SkipInstallerCompile requires -SkipReleaseBuild.'
}

if (-not $SkipReleaseBuild) {
    $releaseArgs = @{}
    if ($Godot) { $releaseArgs.Godot = $Godot }
    if ($TemplateArchive) { $releaseArgs.TemplateArchive = $TemplateArchive }
    if ($VCRuntimeDirectory) { $releaseArgs.VCRuntimeDirectory = $VCRuntimeDirectory }
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
if (-not $InnoCompiler -and -not $SkipInstallerCompile) {
    throw 'Inno Setup ISCC.exe was not found. Install Inno Setup 7 or pass -InnoCompiler.'
}

$projectText = Get-Content (Join-Path $projectRoot 'project.godot') -Raw
$versionMatch = [regex]::Match($projectText, '(?m)^config/version="([0-9]+\.[0-9]+\.[0-9]+)"$')
if (-not $versionMatch.Success) { throw 'project.godot config/version must use x.y.z.' }
$version = $versionMatch.Groups[1].Value
$outputDir = Join-Path $projectRoot 'dist'
$scriptPath = Join-Path $projectRoot 'installer/ScreenPlayer.iss'

if (-not $SkipInstallerCompile) {
    & $InnoCompiler "/DAppVersion=$version" "/DSourceDir=$releaseDir" `
        "/DOutputDir=$outputDir" $scriptPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$installerPath = Join-Path $outputDir "ScreenPlayer-Setup-$version.exe"
if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "Installer was not created: $installerPath"
}
$installer = Get-Item -LiteralPath $installerPath
if ($SkipInstallerCompile) {
    $latestInput = @((Get-Item -LiteralPath $scriptPath)) + @(Get-ChildItem -LiteralPath $releaseDir -File -Recurse)
    if (@($latestInput | Where-Object { $_.LastWriteTimeUtc -gt $installer.LastWriteTimeUtc }).Count) {
        throw 'The installer is older than its inputs. Rebuild it without -SkipInstallerCompile.'
    }
}
$hash = Get-FileHash -LiteralPath $installerPath -Algorithm SHA256
Write-Host "Installer: $($installer.FullName)"
Write-Host ("Size:      {0:N2} MB" -f ($installer.Length / 1MB))
Write-Host "SHA256:    $($hash.Hash)"

$hashLine = $hash.Hash + '  ' + $installer.Name
Set-Content -LiteralPath "$installerPath.sha256" -Value $hashLine -Encoding ASCII
if (-not $IncludeTempWorkaround) { return }

# The Inno loader uses TEMP before its installation script is initialized.
# Ship a launcher that probes a writable directory and scopes TEMP/TMP to Setup.
$launcherSource = Join-Path $projectRoot 'installer/Install-ScreenPlayer.cmd'
$launcherText = [IO.File]::ReadAllText($launcherSource).Replace('@APP_VERSION@', $version)
[IO.File]::WriteAllText((Join-Path $outputDir 'Install-ScreenPlayer.cmd'),
    $launcherText.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
Copy-Item -LiteralPath (Join-Path $projectRoot 'installer/Install-ScreenPlayer.ps1') -Destination $outputDir -Force
$instructionsPath = Join-Path $outputDir 'INSTALL.txt'
$instructions = [IO.File]::ReadAllText((Join-Path $projectRoot 'installer/INSTALL.txt'))
[IO.File]::WriteAllText($instructionsPath, $instructions, (New-Object Text.UTF8Encoding($true)))
$bundlePath = Join-Path $outputDir "ScreenPlayer-Install-$version.zip"
Compress-Archive -LiteralPath @($installerPath, "$installerPath.sha256",
    (Join-Path $outputDir 'Install-ScreenPlayer.cmd'),
    (Join-Path $outputDir 'Install-ScreenPlayer.ps1'), $instructionsPath) -DestinationPath $bundlePath -Force
$bundleHash = Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256
Set-Content -LiteralPath "$bundlePath.sha256" -Value ($bundleHash.Hash + '  ' + (Split-Path $bundlePath -Leaf)) -Encoding ASCII
Write-Host "Install bundle: $bundlePath (extract, then run Install-ScreenPlayer.cmd)"
